defmodule ObserverWeb.Tracer.Tool.Count do
  @moduledoc """
  Tallies `:call` events.

  Ported and adapted from https://github.com/gabiz/tracer's `Tracer.Tool.Count`. Upstream groups
  counts by the values bound in a match spec's `message(...)` action via its own expression-based
  match DSL (each bound variable becomes a `[name, value]` pair). Observer Web doesn't bring that
  DSL over - the existing return_trace/exception_trace/caller/process_dump match specs each
  produce a single raw term instead (e.g. `caller()`'s calling pid), so there's no `[name, value]`
  list to unpack. Counts are grouped by the traced `{mod, fun, arity}` plus that raw message value.
  """

  alias __MODULE__
  alias ObserverWeb.Tracer.Tool.EventCall

  @type t :: %__MODULE__{counts: %{optional(tuple()) => non_neg_integer()}}

  defstruct counts: %{}

  @spec new :: t()
  def new, do: %Count{}

  @spec handle_event(t(), struct()) :: t()
  def handle_event(%Count{counts: counts} = state, %EventCall{
        mod: mod,
        fun: fun,
        arity: arity,
        message: message
      }) do
    key = {mod, fun, arity, message_repr(message)}
    %{state | counts: Map.update(counts, key, 1, &(&1 + 1))}
  end

  def handle_event(state, _event), do: state

  @spec handle_stop(t()) :: [{tuple(), non_neg_integer()}]
  def handle_stop(%Count{counts: counts}) do
    counts
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp message_repr(nil), do: nil
  defp message_repr(term), do: inspect(term)
end
