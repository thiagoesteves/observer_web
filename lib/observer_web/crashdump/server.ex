defmodule ObserverWeb.Crashdump.Server do
  @moduledoc """
  Owns the interaction with OTP's `:crashdump_viewer` parser (a globally named gen_server):
  starts it on demand, serializes dump loads, receives the parser's progress reports and
  broadcasts them, and decodes its records into maps for the Crashdump page.

  Progress: while loading, this server registers itself under the name the parser reports to
  (`:cdv_progress_handler`, a no-op destination when unregistered) and receives
  `{:progress, {:ok, phase | percent | :done}}` / `{:progress, {:error, reason}}` messages,
  re-broadcast on the `"crashdump"` PubSub topic.

  Decoding: `#general_info{}`/`#proc{}` records are converted by zipping their documented field
  order over the tuple - a dump/record from a different OTP release with more or fewer fields
  degrades to the fields both sides know instead of crashing.
  """

  use GenServer

  @progress_handler :cdv_progress_handler
  @query_timeout :timer.minutes(2)

  @general_info_fields ~w(created slogan system_vsn compile_time taints node_name num_atoms
                          num_procs num_ets num_timers num_fun mem_tot mem_max instr_info
                          thread)a

  @proc_fields ~w(pid name init_func parent start_time state current_func msg_q_len msg_q
                  last_calls links monitors mon_by prog_count cp arity dict reds num_heap_frag
                  heap_frag_data stack_heap old_heap heap_unused old_heap_unused bin_vheap
                  old_bin_vheap bin_vheap_unused old_bin_vheap_unused new_heap_start
                  new_heap_top stack_top stack_end old_heap_start old_heap_top old_heap_end
                  memory stack_dump run_queue int_state)a

  @summary_fields ~w(pid name state current_func msg_q_len reds memory stack_heap)a

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec load(String.t()) :: :ok | {:error, term()}
  def load(path), do: GenServer.call(__MODULE__, {:load, path}, @query_timeout)

  @spec status() :: :idle | {:loading, String.t(), non_neg_integer()} | {:loaded, String.t()}
  def status, do: GenServer.call(__MODULE__, :status)

  @spec general_info() :: {:ok, map()} | {:error, :no_dump_loaded}
  def general_info, do: GenServer.call(__MODULE__, :general_info, @query_timeout)

  @spec processes() :: {:ok, [map()]} | {:error, :no_dump_loaded}
  def processes, do: GenServer.call(__MODULE__, :processes, @query_timeout)

  @spec proc_details(String.t()) :: {:ok, map()} | {:error, :no_dump_loaded | :not_found}
  def proc_details(pid_string),
    do: GenServer.call(__MODULE__, {:proc_details, pid_string}, @query_timeout)

  @impl true
  def init(_args) do
    Process.flag(:trap_exit, true)

    {:ok, %{status: :idle, percent: 0, phase: nil, relay: nil}}
  end

  @impl true
  def handle_call({:load, _path}, _from, %{status: {:loading, _, _}} = state) do
    {:reply, {:error, :load_in_progress}, state}
  end

  def handle_call({:load, path}, _from, state) do
    with :ok <- ensure_viewer_started(),
         {:ok, relay} <- start_progress_relay() do
      :crashdump_viewer.read_file(String.to_charlist(path))

      broadcast({:crashdump_progress, {:loading, path, 0}})

      {:reply, :ok, %{state | status: {:loading, path, 0}, percent: 0, phase: nil, relay: relay}}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call(:status, _from, %{status: status} = state) do
    {:reply, status, state}
  end

  def handle_call(:general_info, _from, %{status: {:loaded, _path}} = state) do
    {:ok, info, _truncation_warning} = :crashdump_viewer.general_info()

    {:reply, {:ok, decode(info, @general_info_fields)}, state}
  end

  def handle_call(:processes, _from, %{status: {:loaded, _path}} = state) do
    {:ok, procs, _truncation_warning} = :crashdump_viewer.processes()

    summaries =
      Enum.map(procs, fn proc ->
        proc |> decode(@proc_fields) |> Map.take(@summary_fields)
      end)

    {:reply, {:ok, summaries}, state}
  end

  def handle_call({:proc_details, pid_string}, _from, %{status: {:loaded, _path}} = state) do
    case :crashdump_viewer.proc_details(String.to_charlist(pid_string)) do
      {:ok, proc, _truncation_warning} -> {:reply, {:ok, decode(proc, @proc_fields)}, state}
      {:error, _not_found} -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(_query, _from, state) do
    {:reply, {:error, :no_dump_loaded}, state}
  end

  @impl true
  def handle_info({:progress, {:ok, :done}}, %{status: {:loading, path, _pct}} = state) do
    release_progress_handler(state)
    broadcast({:crashdump_progress, {:loaded, path}})

    {:noreply, %{state | status: {:loaded, path}, relay: nil}}
  end

  def handle_info({:progress, {:ok, percent}}, %{status: {:loading, path, _pct}} = state)
      when is_integer(percent) do
    broadcast({:crashdump_progress, {:loading, path, percent}})

    {:noreply, %{state | status: {:loading, path, percent}, percent: percent}}
  end

  # A new parsing phase, e.g. ~c"Reading file" / ~c"Processing terms"
  def handle_info({:progress, {:ok, phase}}, %{status: {:loading, path, pct}} = state) do
    broadcast({:crashdump_progress, {:loading, path, pct}})

    {:noreply, %{state | phase: to_string(phase)}}
  end

  def handle_info({:progress, {:error, reason}}, state) do
    release_progress_handler(state)
    broadcast({:crashdump_progress, {:error, reason}})

    {:noreply, %{state | status: :idle, percent: 0, phase: nil, relay: nil}}
  end

  # A normal exit is the relay wrapping up - anything else is the linked parser gen_server
  # dying, e.g. a corrupt dump crashing it mid-parse
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:EXIT, _pid, reason}, state) do
    release_progress_handler(state)

    if match?({:loading, _, _}, state.status) do
      broadcast({:crashdump_progress, {:error, reason}})
    end

    {:noreply, %{state | status: :idle, percent: 0, phase: nil, relay: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp ensure_viewer_started do
    case :crashdump_viewer.start_link() do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      # coveralls-ignore-start
      {:error, _reason} = error ->
        error
        # coveralls-ignore-stop
    end
  end

  # The parser reports progress to whatever process holds the @progress_handler registered name
  # (and safely no-ops when nobody does). A process can only carry one registered name and this
  # server already has one, so a tiny linked relay holds the name while loading and forwards the
  # {:progress, _} messages here. A name clash means the crashdump_viewer GUI is open on this
  # node.
  defp start_progress_relay do
    server = self()

    relay =
      spawn_link(fn ->
        try do
          Process.register(self(), @progress_handler)
          send(server, {:relay_registered, self(), :ok})
          relay_loop(server)
        rescue
          ArgumentError -> send(server, {:relay_registered, self(), :busy})
        end
      end)

    receive do
      {:relay_registered, ^relay, :ok} -> {:ok, relay}
      {:relay_registered, ^relay, :busy} -> {:error, :progress_handler_busy}
    after
      1_000 ->
        # coveralls-ignore-start
        {:error, :progress_handler_busy}
        # coveralls-ignore-stop
    end
  end

  defp relay_loop(server) do
    receive do
      :stop ->
        :ok

      message ->
        send(server, message)
        relay_loop(server)
    end
  end

  defp release_progress_handler(%{relay: relay}) when is_pid(relay) do
    send(relay, :stop)
    :ok
  end

  defp release_progress_handler(_state), do: :ok

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(ObserverWeb.PubSub, "crashdump", message)
  end

  # Zips the record's documented field order over the tuple, converting charlists to strings
  # and inspecting other terms - tolerant of records with more or fewer fields than expected.
  defp decode(record, fields) when is_tuple(record) do
    [_tag | values] = Tuple.to_list(record)

    fields
    |> Enum.zip(values)
    |> Map.new(fn {field, value} -> {field, present(value)} end)
  end

  defp present(value) when is_integer(value) or is_binary(value), do: value
  defp present(:undefined), do: nil

  # Pids/ports round-trip through the parser's own textual form ("<0.59.0>"), which
  # proc_details/1 expects back as its lookup key.
  defp present(value) when is_pid(value), do: to_string(:erlang.pid_to_list(value))
  defp present(value) when is_port(value), do: to_string(:erlang.port_to_list(value))

  defp present(value) when is_list(value) do
    if List.ascii_printable?(value) do
      to_string(value)
    else
      inspect(value, limit: 100, printable_limit: 4_096)
    end
  end

  defp present(value), do: inspect(value, limit: 100, printable_limit: 4_096)
end
