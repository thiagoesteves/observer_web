defmodule ObserverWeb.Tracer.Tool do
  @moduledoc """
  Dispatches raw `:dbg` trace events to the active tool's aggregation logic.

  This intentionally does not port `tracer`'s `use Tracer.Tool` probe/agent_opts plumbing (see
  https://github.com/gabiz/tracer) - session management (timeouts, max message caps, multi-node
  dispatch) is already handled by `ObserverWeb.Tracer.Server`, so only the per-tool
  init/handle_event/handle_stop aggregation logic is ported.
  """

  alias ObserverWeb.Tracer.Tool.CallSeq
  alias ObserverWeb.Tracer.Tool.Count
  alias ObserverWeb.Tracer.Tool.Duration
  alias ObserverWeb.Tracer.Tool.Event
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventIn
  alias ObserverWeb.Tracer.Tool.EventOut
  alias ObserverWeb.Tracer.Tool.EventReturnFrom
  alias ObserverWeb.Tracer.Tool.EventReturnTo

  @type t :: :display | :count | :duration | :call_seq

  @doc """
  `:dbg` trace flags required to run the given tool (always includes `:c` and `:timestamp`).

  `:display` needs full call argument values for its live log, so it's traced without `:arity`
  (the raw event's `{mod, fun, _}` element holds the argument list). Every other tool aggregates by
  `{mod, fun, arity}`, so `:arity` is requested to get the integer directly instead of a list of
  argument values.
  """
  @spec dbg_flags(t()) :: [atom()]
  def dbg_flags(:display), do: [:c, :timestamp]
  def dbg_flags(:count), do: [:c, :timestamp, :arity]
  def dbg_flags(:duration), do: [:c, :timestamp, :arity]
  def dbg_flags(:call_seq), do: [:c, :timestamp, :arity]

  @doc """
  Match spec keys forced onto every traced function for this tool, regardless of what's selected
  in the UI (the Profiling page has no match-spec picker of its own - see
  `Observer.Web.Profiling.Page`). `:duration` needs `return_trace()` to see `:return_from` events.
  `:call_seq` needs both `return_trace()` and argument capture, combined into the single `call_seq`
  match spec - see `ObserverWeb.Tracer.get_default_functions_matchspecs/0` for why selecting both
  `return_trace` and `capture_args` separately wouldn't work.
  """
  @spec forced_match_spec_keys(t()) :: [String.t()]
  def forced_match_spec_keys(:duration), do: ["return_trace"]
  def forced_match_spec_keys(:call_seq), do: ["call_seq"]
  def forced_match_spec_keys(_tool), do: []

  @doc """
  Builds the initial aggregation state for the given tool.
  """
  @spec init(t(), map()) :: term()
  def init(:count, _opts), do: Count.new()
  def init(:duration, opts), do: Duration.new(opts)
  def init(:call_seq, _opts), do: CallSeq.new()

  @doc """
  Translates a raw `:dbg` trace message into an event struct and folds it into the tool's state.
  """
  @spec handle_event(t(), tuple(), term()) :: term()
  def handle_event(:count, trace_ms, state), do: Count.handle_event(state, from_trace(trace_ms))

  def handle_event(:duration, trace_ms, state),
    do: Duration.handle_event(state, from_trace(trace_ms))

  def handle_event(:call_seq, trace_ms, state),
    do: CallSeq.handle_event(state, from_trace(trace_ms))

  @doc """
  Finalizes the tool's state into the report sent back to the requesting LiveView.
  """
  @spec handle_stop(t(), term()) :: term()
  def handle_stop(:count, state), do: Count.handle_stop(state)
  def handle_stop(:duration, state), do: Duration.handle_stop(state)
  def handle_stop(:call_seq, state), do: CallSeq.handle_stop(state)

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

  def from_trace({:trace_ts, pid, :out, {m, f, a}, ts}),
    do: %EventOut{mod: m, fun: f, arity: a, pid: pid, ts: ts}

  # coveralls-ignore-start
  def from_trace(trace_ms), do: %Event{event: trace_ms}
  # coveralls-ignore-stop
end
