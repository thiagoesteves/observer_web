defmodule ObserverWeb.Tracer.Tool.Duration do
  @moduledoc """
  Measures how long traced functions take to run, per process, optionally reduced through an
  aggregation mode (`:sum`, `:avg`, `:min`, `:max`, `:dist`).

  Ported and adapted from https://github.com/gabiz/tracer's `Tracer.Tool.Duration`:

    * Fixes a typo in the upstream aggregation lookup that maps the atom `:mix` (instead of
      `:min`) to `Enum.min/1` - upstream's `:min` mode is unreachable and raises.
    * Upstream streams each duration live as it completes when no aggregation mode is selected,
      and only reports finalized aggregates through `handle_stop/1` otherwise. Observer Web's tool
      sessions only ever produce a single report at the end (see `ObserverWeb.Tracer.Server`), so
      this always collects every sample and reports them all at once - individually when there's
      no aggregation mode, reduced when there is.
    * Requires `return_trace()` in the match spec to see `:return_from` events -
      `ObserverWeb.Tracer.Tool.forced_match_spec_keys/1` forces this in regardless of the match
      specs selected in the UI.

  Samples are grouped (and, when an aggregation mode is selected, reduced) by the reporting node
  in addition to `{mod, fun, arity}` and the raw message value, so tracing the same function
  across multiple nodes doesn't collapse their durations together - matching how Live Tracing
  identifies which node ("service") each event came from.
  """

  alias __MODULE__
  alias ObserverWeb.Tracer.Tool.Collect
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnFrom

  @type aggregation :: :sum | :avg | :min | :max | :dist | nil

  @type t :: %__MODULE__{
          aggregation: aggregation(),
          stacks: %{optional(pid()) => list()},
          collect: Collect.t()
        }

  defstruct aggregation: nil, stacks: %{}, collect: nil

  @spec new(map()) :: t()
  def new(opts \\ %{}) do
    %Duration{aggregation: Map.get(opts, :aggregation), collect: Collect.new()}
  end

  @spec handle_event(t(), struct()) :: t()
  def handle_event(%Duration{stacks: stacks} = state, %EventCall{
        pid: pid,
        mod: mod,
        fun: fun,
        arity: arity,
        ts: ts,
        message: message
      }) do
    entry = {mod, fun, arity, ts_to_us(ts), message}
    %{state | stacks: Map.update(stacks, pid, [entry], &[entry | &1])}
  end

  def handle_event(
        %Duration{stacks: stacks, collect: collect} = state,
        %EventReturnFrom{pid: pid, mod: mod, fun: fun, arity: arity, ts: ts}
      ) do
    exit_ts = ts_to_us(ts)

    case Map.get(stacks, pid, []) do
      # Ignore recursive self-calls: only pop once the frame below is a *different* invocation
      # of the same {mod, fun, arity}, so the reported duration covers the outermost call.
      [{^mod, ^fun, ^arity, _entry_ts, _message}, {^mod, ^fun, ^arity, entry_ts, message} | rest] ->
        %{state | stacks: Map.put(stacks, pid, [{mod, fun, arity, entry_ts, message} | rest])}

      [{^mod, ^fun, ^arity, entry_ts, message} | rest] ->
        duration = exit_ts - entry_ts
        key = {node(pid), mod, fun, arity, message_repr(message)}
        collect = Collect.add_sample(collect, key, duration)
        %{state | stacks: Map.put(stacks, pid, rest), collect: collect}

      _no_matching_entry ->
        state
    end
  end

  def handle_event(state, _event), do: state

  @spec handle_stop(t()) :: [{tuple(), term()}]
  def handle_stop(%Duration{aggregation: nil, collect: collect}) do
    collect
    |> Collect.get_collections()
    |> Enum.flat_map(fn {key, samples} -> Enum.map(samples, &{key, &1}) end)
  end

  def handle_stop(%Duration{aggregation: aggregation, collect: collect}) do
    collect
    |> Collect.get_collections()
    |> Enum.map(fn {key, samples} -> {key, aggregate(aggregation, samples)} end)
  end

  defp aggregate(:sum, samples), do: Enum.sum(samples)
  defp aggregate(:min, samples), do: Enum.min(samples)
  defp aggregate(:max, samples), do: Enum.max(samples)
  defp aggregate(:avg, samples), do: Enum.sum(samples) / length(samples)

  defp aggregate(:dist, samples) do
    Enum.reduce(samples, %{}, fn value, buckets ->
      bucket = log_bucket(value)
      Map.update(buckets, bucket, 1, &(&1 + 1))
    end)
  end

  # Buckets a value into the nearest power-of-two boundary (the `+ 0.01` keeps a value of `0`
  # from being undefined in the log).
  defp log_bucket(value) do
    round(:math.pow(2, Float.floor(:math.log(value + 0.01) / :math.log(2))))
  end

  defp ts_to_us({mega, seconds, micro}), do: (mega * 1_000_000 + seconds) * 1_000_000 + micro

  defp message_repr(nil), do: nil
  defp message_repr(term), do: inspect(term)
end
