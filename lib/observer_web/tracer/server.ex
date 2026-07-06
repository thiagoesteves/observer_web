defmodule ObserverWeb.Tracer.Server do
  @moduledoc """
  This server is responsible for handling tracing requests.

  Inspired by:
   * https://www.erlang.org/docs/24/man/dbg
   * https://github.com/erlang/otp/blob/master/lib/observer/src/observer_trace_wx.erl
   * https://kaiwern.com/posts/2020/11/02/debugging-with-tracing-in-elixir/
   * https://blog.appsignal.com/2023/01/10/debugging-and-tracing-in-erlang.html
   * https://github.dev/massemanet/redbug
  """
  use GenServer
  require Logger

  alias ObserverWeb.Common
  alias ObserverWeb.Tracer
  alias ObserverWeb.Tracer.Tool

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, %Tracer{}}
  end

  @impl true
  def handle_call(
        {:stop_tracing, rcv_session_id},
        _from,
        %Tracer{
          session_id: session_id
        } = state
      )
      when rcv_session_id == session_id do
    :dbg.stop()

    maybe_report_tool_result(state)

    {:reply, :ok, %Tracer{}}
  end

  def handle_call({:stop_tracing, _rcv_session_id}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(
        {:start_trace, _new_state},
        _from,
        %Tracer{status: :running} = state
      ) do
    {:reply, {:error, :already_started}, state}
  end

  # credo:disable-for-lines:1
  def handle_call(
        {:start_trace,
         %{
           max_messages: max_messages,
           session_id: session_id,
           request_pid: request_pid,
           functions_by_node: functions_by_node,
           session_timeout_ms: session_timeout_ms
         } = new_state},
        _from,
        _state
      ) do
    Process.monitor(request_pid)

    tracer_pid = self()
    # The local node is always present in the trace list of nodes.
    # The following list will indicate to the trace handler whether the node
    # should be included or filtered out.
    monitored_nodes = Map.keys(functions_by_node)

    tool = new_state.tool
    tool_state = if tool == :display, do: nil, else: Tool.init(tool, new_state.tool_opts)
    forced_match_spec_keys = Tool.forced_match_spec_keys(tool)
    trace_pattern_fun = if Tool.local_tracing?(tool), do: &:dbg.tpl/4, else: &:dbg.tp/4

    session_info = %{
      session_id: session_id,
      tracer_pid: tracer_pid,
      request_pid: request_pid,
      monitored_nodes: monitored_nodes,
      max_messages: max_messages
    }

    default_functions_matchspecs = Tracer.get_default_functions_matchspecs()

    # Start Tracer with Handler Function
    :dbg.tracer(:process, {&handle_trace/2, {session_info, 1, tool, tool_state}})

    Enum.each(functions_by_node, fn {node, functions} ->
      # Add node to tracing process (exclude local node since it is added by default)
      # coveralls-ignore-start
      if node != Node.self() do
        :dbg.n(node)
      end

      # coveralls-ignore-stop

      # Add functions to be traced
      # credo:disable-for-lines:12
      Enum.each(functions, fn function ->
        match_spec_keys = Enum.uniq(function.match_spec ++ forced_match_spec_keys)

        match_specs =
          Enum.reduce(match_spec_keys, [], fn spec, acc ->
            atom_spec = String.to_existing_atom(spec)

            case Map.get(default_functions_matchspecs, atom_spec) do
              # coveralls-ignore-start
              nil -> acc
              # coveralls-ignore-stop
              %{pattern: pattern} -> acc ++ pattern
            end
          end)

        trace_pattern_fun.(function.module, function.function, function.arity, match_specs)
      end)
    end)

    # :all -> All processes and ports in the system as well as all processes and ports
    #         created hereafter are to be traced.
    # :c -> Traces global function calls for the process according to the trace patterns
    #       set in the system (see tp/2).
    :dbg.p(:all, Tool.dbg_flags(tool))

    Process.send_after(self(), {:trace_session_timeout, session_id}, session_timeout_ms)

    new_state = %{new_state | status: :running, tool_state: tool_state}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_info(
        {:trace_session_timeout, rcv_session_id} = msg,
        %Tracer{
          session_id: session_id,
          request_pid: request_pid
        } = state
      )
      when rcv_session_id == session_id do
    :dbg.stop()

    maybe_report_tool_result(state)

    send(request_pid, msg)

    {:noreply, %Tracer{}}
  end

  def handle_info({:trace_session_timeout, _rcv_session_id}, state) do
    {:noreply, state}
  end

  # NOTE: Mirrors the tool's aggregation state (accumulated inside the separate process :dbg
  # spawns for the tracer handler fun) so it's available here if the session ends via an explicit
  # stop_trace/1 call or a timeout, neither of which run inside handle_trace/2.
  def handle_info(
        {:tool_state_update, rcv_session_id, tool_state},
        %Tracer{
          session_id: session_id
        } = state
      )
      when rcv_session_id == session_id do
    {:noreply, %{state | tool_state: tool_state}}
  end

  def handle_info({:tool_state_update, _rcv_session_id, _tool_state}, state) do
    {:noreply, state}
  end

  # NOTE: Messages from handle_trace
  def handle_info({:stop_tracing, rcv_session_id} = msg, %Tracer{
        session_id: session_id,
        max_messages: _max_messages,
        request_pid: request_pid
      })
      when rcv_session_id == session_id do
    send(request_pid, msg)

    {:noreply, %Tracer{}}
  end

  def handle_info({:stop_tracing, _session_id}, state) do
    {:noreply, state}
  end

  # NOTE: Request PID process was terminated
  def handle_info(
        {:DOWN, _reference, :process, target_pid, _reason},
        %{request_pid: request_pid}
      )
      when target_pid == request_pid do
    :dbg.stop()

    {:noreply, %Tracer{}}
  end

  def handle_info({:DOWN, _reference, :process, _target_pid, _reason}, state) do
    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec start_trace(functions :: list(), attrs :: map()) ::
          {:ok, Tracer.t()} | {:error, :already_started}
  def start_trace(functions, attrs) do
    GenServer.call(
      __MODULE__,
      {:start_trace,
       struct(
         Tracer,
         attrs
         |> Map.put(:request_pid, self())
         |> Map.put(:session_id, Common.uuid4())
         |> Map.put(:functions_by_node, Enum.group_by(functions, & &1.node))
       )}
    )
  end

  @spec stop_trace(binary()) :: :ok
  def stop_trace(session_id) do
    GenServer.call(__MODULE__, {:stop_tracing, session_id})
  end

  @spec state :: Tracer.t()
  def state do
    GenServer.call(__MODULE__, :state)
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================

  defp maybe_report_tool_result(%Tracer{tool: :display}), do: :ok

  defp maybe_report_tool_result(%Tracer{
         tool: tool,
         tool_state: tool_state,
         session_id: session_id,
         request_pid: request_pid
       }) do
    report = Tool.handle_stop(tool, tool_state)
    send(request_pid, {:tool_report, session_id, report})
  end

  def handle_trace(
        _trace_message,
        {%{max_messages: max_messages} = session_info, index, tool, tool_state}
      )
      when index > max_messages do
    # coveralls-ignore-start
    :dbg.stop()
    # coveralls-ignore-stop
    {session_info, index, tool, tool_state}
  end

  def handle_trace(
        trace_ms,
        {%{
           session_id: session_id,
           tracer_pid: tracer_pid,
           request_pid: request_pid,
           monitored_nodes: monitored_nodes,
           max_messages: max_messages
         } = session_info, index, tool, tool_state}
      ) do
    # NOTE: only :display is decoded into a formatted string here - other tools trace with
    # different dbg flags (see Tool.dbg_flags/1, e.g. :arity instead of full argument values), so
    # this decode can't be reused for them. They only need the origin pid for the monitored_nodes
    # check, which is always the trace tuple's 2nd element regardless of flags.
    {origin_pid, type, message} =
      if tool == :display do
        decode_display_message(trace_ms, index)
      else
        {elem(trace_ms, 1), nil, nil}
      end

    node = origin_pid && :erlang.node(origin_pid)

    if node in monitored_nodes do
      tool_state = dispatch_to_tool(tool, tool_state, trace_ms, tracer_pid, session_id)

      if tool == :display do
        send(request_pid, {:new_trace_message, session_id, node, index, type, message})
      end

      if index == max_messages do
        stop_max_messages_reached(tool, tool_state, session_id, tracer_pid, request_pid)
      else
        {session_info, index + 1, tool, tool_state}
      end
    else
      {session_info, index, tool, tool_state}
    end
  end

  defp stop_max_messages_reached(tool, tool_state, session_id, tracer_pid, request_pid) do
    unless tool == :display do
      report = Tool.handle_stop(tool, tool_state)
      send(request_pid, {:tool_report, session_id, report})
    end

    send(tracer_pid, {:stop_tracing, session_id})
    send(request_pid, {:stop_tracing, session_id})
    :dbg.stop()
  end

  defp decode_display_message(trace_ms, index) do
    case trace_ms do
      {_, pid, :call = type, {module, fun, args}, caller, timestamp} ->
        {{y, mm, d}, {h, m, s}} = :calendar.now_to_datetime(timestamp)
        arg_list = Enum.map(args, &inspect/1)

        {pid, type,
         "[#{y}-#{mm}-#{d} #{h}:#{m}:#{s}] (#{inspect(pid)}) #{inspect(module)}.#{fun}(#{Enum.join(arg_list, ", ")}) caller: #{inspect(caller)}"}

      {_, pid, :call = type, {module, fun, args}, timestamp} ->
        {{y, mm, d}, {h, m, s}} = :calendar.now_to_datetime(timestamp)
        arg_list = Enum.map(args, &inspect/1)

        {pid, type,
         "[#{y}-#{mm}-#{d} #{h}:#{m}:#{s}] (#{inspect(pid)}) #{inspect(module)}.#{fun}(#{Enum.join(arg_list, ", ")})"}

      {_, pid, :return_from = type, {module, fun, arity}, return_value, timestamp} ->
        {{y, mm, d}, {h, m, s}} = :calendar.now_to_datetime(timestamp)

        {pid, type,
         "[#{y}-#{mm}-#{d} #{h}:#{m}:#{s}] (#{inspect(pid)}) #{inspect(module)}.#{fun}/#{arity}}) return_value: #{inspect(return_value)}"}

      {_, pid, :exception_from = type, {module, fun, arity}, exception_value, timestamp} ->
        {{y, mm, d}, {h, m, s}} = :calendar.now_to_datetime(timestamp)

        {pid, type,
         "[#{y}-#{mm}-#{d} #{h}:#{m}:#{s}] (#{inspect(pid)}) #{inspect(module)}.#{fun}/#{arity}}) exception_value: #{inspect(exception_value)}"}

      # coveralls-ignore-start
      trace_msg ->
        Logger.warning(
          "Not able to decode trace_mg: #{inspect(trace_msg)} session_index: #{inspect(index)}"
        )

        {nil, nil, nil}
        # coveralls-ignore-stop
    end
  end

  defp dispatch_to_tool(:display, tool_state, _trace_ms, _tracer_pid, _session_id), do: tool_state

  defp dispatch_to_tool(tool, tool_state, trace_ms, tracer_pid, session_id) do
    new_tool_state = Tool.handle_event(tool, trace_ms, tool_state)
    send(tracer_pid, {:tool_state_update, session_id, new_tool_state})
    new_tool_state
  end
end
