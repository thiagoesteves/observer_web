defmodule ObserverWeb.Tracer.Tool do
  @moduledoc """
  Dispatches raw `:dbg` trace events to the active tool's aggregation logic.

  This intentionally does not port `tracer`'s `use Tracer.Tool` probe/agent_opts plumbing (see
  https://github.com/gabiz/tracer) - session management (timeouts, max message caps, multi-node
  dispatch) is already handled by `ObserverWeb.Tracer.Server`, so only the per-tool
  init/handle_event/handle_stop aggregation logic is ported.
  """

  alias ObserverWeb.Rpc
  alias ObserverWeb.Tracer.Tool.CallSeq
  alias ObserverWeb.Tracer.Tool.Count
  alias ObserverWeb.Tracer.Tool.Duration
  alias ObserverWeb.Tracer.Tool.Event
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventIn
  alias ObserverWeb.Tracer.Tool.EventOut
  alias ObserverWeb.Tracer.Tool.EventReturnFrom
  alias ObserverWeb.Tracer.Tool.EventReturnTo
  alias ObserverWeb.Tracer.Tool.FlameGraph

  @type t :: :display | :count | :duration | :call_seq | :flame_graph

  @doc """
  Human-readable label for a traced process, resolved with the same fallback chain `etop` uses:
  the registered name when it has one, otherwise the `Process.set_label/1` process label,
  otherwise the `proc_lib` initial call (how GenServers, Supervisors and Tasks identify
  themselves) suffixed with the pid to keep concurrent instances of the same module apart, and
  finally the inspected pid alone.

  Works for local and remote pids (`ObserverWeb.Rpc.pinfo/2` is location transparent) - most
  traced processes on a remote node aren't locally registered (Registry/`:via` registrations
  don't set `:registered_name`), so the fallbacks are what keep multi-node reports readable.
  Falls back to the pid when the process has already died by the time the report is built -
  common for short-lived traced processes.
  """
  @spec process_label(pid()) :: String.t()
  def process_label(pid) do
    # The whole dictionary is fetched instead of the leaner `{:dictionary, :"$process_label"}`
    # item form because the latter requires OTP 26.2+ on the *observed* node.
    case Rpc.pinfo(pid, [:registered_name, :dictionary, :initial_call]) do
      [{:registered_name, name}, {:dictionary, dictionary}, {:initial_call, initial_call}] ->
        registered_label(name) || dictionary_label(dictionary) ||
          initial_call_label(dictionary, initial_call, pid) || inspect(pid)

      _dead ->
        inspect(pid)
    end
  end

  # An alive-but-unregistered process reports [] as its registered name.
  defp registered_label(name) when is_atom(name) and name != nil, do: inspect(name)
  defp registered_label(_unregistered), do: nil

  defp dictionary_label(dictionary) when is_list(dictionary) do
    case List.keyfind(dictionary, :"$process_label", 0) do
      {_key, label} when is_binary(label) -> label
      {_key, label} -> inspect(label)
      nil -> nil
    end
  end

  defp dictionary_label(_no_dictionary), do: nil

  # proc_lib-spawned processes carry their real starting MFA in the :"$initial_call" dictionary
  # entry; the raw :initial_call for them is the meaningless proc_lib/erlang wrapper. Anything
  # without the dictionary entry that only reports a generic spawn wrapper keeps the plain pid.
  defp initial_call_label(dictionary, initial_call, pid) do
    initial_call =
      case is_list(dictionary) && List.keyfind(dictionary, :"$initial_call", 0) do
        {_key, {_m, _f, _a} = mfa} -> mfa
        _no_entry -> initial_call
      end

    case initial_call do
      {mod, _f, _a} when mod in [:erlang, :proc_lib] -> nil
      {mod, fun, arity} -> "#{inspect(mod)}.#{fun}/#{arity} #{inspect(pid)}"
      _unknown -> nil
    end
  end

  @doc """
  `:dbg` trace flags required to run the given tool (always includes `:c` and `:timestamp`).

  `:display` needs full call argument values for its live log, so it's traced without `:arity`
  (the raw event's `{mod, fun, _}` element holds the argument list). Every other tool aggregates by
  `{mod, fun, arity}`, so `:arity` is requested to get the integer directly instead of a list of
  argument values. `:flame_graph` additionally needs `:return_to` to unwind the stack without a
  match spec per function (see `ObserverWeb.Tracer.Tool.FlameGraph` for why `:running` isn't used
  here despite upstream using it).
  """
  @spec dbg_flags(t()) :: [atom()]
  def dbg_flags(:display), do: [:c, :timestamp]
  def dbg_flags(:count), do: [:c, :timestamp, :arity]
  def dbg_flags(:duration), do: [:c, :timestamp, :arity]
  def dbg_flags(:call_seq), do: [:c, :timestamp, :arity]
  def dbg_flags(:flame_graph), do: [:c, :timestamp, :arity, :return_to]

  @doc """
  Match spec keys forced onto every traced function for this tool, regardless of what's selected
  in the UI (the Profiling page has no match-spec picker of its own - see
  `Observer.Web.Profiling.Page`). `:duration` needs `return_trace()` to see `:return_from` events.
  `:call_seq` needs both `return_trace()` and argument capture, combined into the single `call_seq`
  match spec - see `ObserverWeb.Tracer.get_default_functions_matchspecs/0` for why selecting both
  `return_trace` and `capture_args` separately wouldn't work. `:flame_graph` needs no match spec at
  all - it relies purely on the `:return_to` dbg flag to unwind stacks, and traces every call in the
  selected module(s) rather than specific functions.
  """
  @spec forced_match_spec_keys(t()) :: [String.t()]
  def forced_match_spec_keys(:duration), do: ["return_trace"]
  def forced_match_spec_keys(:call_seq), do: ["call_seq"]
  def forced_match_spec_keys(_tool), do: []

  @doc """
  Whether this tool needs LOCAL call tracing (`:dbg.tpl/4`) instead of the default global call
  tracing (`:dbg.tp/4`). Global tracing never emits `:return_to` events at all (regardless of the
  `:return_to` dbg flag) and also misses calls between functions in the same traced module, so
  `:flame_graph` - which needs both - requires local tracing.
  """
  @spec local_tracing?(t()) :: boolean()
  def local_tracing?(:flame_graph), do: true
  def local_tracing?(_tool), do: false

  @doc """
  Builds the initial aggregation state for the given tool.
  """
  @spec init(t(), map()) :: term()
  def init(:count, _opts), do: Count.new()
  def init(:duration, opts), do: Duration.new(opts)
  def init(:call_seq, _opts), do: CallSeq.new()
  def init(:flame_graph, _opts), do: FlameGraph.new()

  @doc """
  Translates a raw `:dbg` trace message into an event struct and folds it into the tool's state.
  """
  @spec handle_event(t(), tuple(), term()) :: term()
  def handle_event(:count, trace_ms, state), do: Count.handle_event(state, from_trace(trace_ms))

  def handle_event(:duration, trace_ms, state),
    do: Duration.handle_event(state, from_trace(trace_ms))

  def handle_event(:call_seq, trace_ms, state),
    do: CallSeq.handle_event(state, from_trace(trace_ms))

  def handle_event(:flame_graph, trace_ms, state),
    do: FlameGraph.handle_event(state, from_trace(trace_ms))

  @doc """
  Finalizes the tool's state into the report sent back to the requesting LiveView.
  """
  @spec handle_stop(t(), term()) :: term()
  def handle_stop(:count, state), do: Count.handle_stop(state)
  def handle_stop(:duration, state), do: Duration.handle_stop(state)
  def handle_stop(:call_seq, state), do: CallSeq.handle_stop(state)
  def handle_stop(:flame_graph, state), do: FlameGraph.handle_stop(state)

  @doc false
  @spec from_trace(tuple()) :: struct()
  def from_trace({:trace_ts, pid, :call, {m, f, a}, message, ts}),
    do: %EventCall{mod: m, fun: f, arity: a, pid: pid, message: message, ts: ts}

  def from_trace({:trace_ts, pid, :call, {m, f, a}, ts}),
    do: %EventCall{mod: m, fun: f, arity: a, pid: pid, ts: ts}

  def from_trace({:trace_ts, pid, :return_from, {m, f, a}, ret, ts}),
    do: %EventReturnFrom{mod: m, fun: f, arity: a, pid: pid, return_value: ret, ts: ts}

  def from_trace({:trace_ts, pid, :return_to, {m, f, a}, ts}),
    do: %EventReturnTo{mod: m, fun: f, arity: a, pid: pid, ts: ts}

  def from_trace({:trace_ts, pid, :return_to, :undefined, ts}),
    do: %EventReturnTo{mod: :undefined, fun: :undefined, arity: 0, pid: pid, ts: ts}

  def from_trace({:trace_ts, pid, :in, {m, f, a}, ts}),
    do: %EventIn{mod: m, fun: f, arity: a, pid: pid, ts: ts}

  # The scheduler reports `0` instead of an MFA when it doesn't know what the process is about to
  # run (e.g. resuming inside a BIF).
  def from_trace({:trace_ts, pid, :in, 0, ts}),
    do: %EventIn{mod: :undefined, fun: :undefined, arity: 0, pid: pid, ts: ts}

  def from_trace({:trace_ts, pid, :out, {m, f, a}, ts}),
    do: %EventOut{mod: m, fun: f, arity: a, pid: pid, ts: ts}

  def from_trace({:trace_ts, pid, :out, 0, ts}),
    do: %EventOut{mod: :undefined, fun: :undefined, arity: 0, pid: pid, ts: ts}

  # coveralls-ignore-start
  def from_trace(trace_ms), do: %Event{event: trace_ms}
  # coveralls-ignore-stop
end
