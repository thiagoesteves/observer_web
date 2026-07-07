defmodule ObserverWeb.Tracer.Tool.CallSeq do
  @moduledoc """
  Builds an indented call-sequence tree per process: every traced call is an "enter" line and
  every matching return is an "exit" line, indented by nesting depth.

  Ported and adapted from https://github.com/gabiz/tracer's `Tracer.Tool.CallSeq`:

    * Drops the `start_match`/`started` gating - upstream can trace a whole process but only start
      recording once a specific function is called. Observer Web already scopes which functions
      can be traced from the Profiling page's own function picker, so there's no separate "start
      match" concept to gate on - every entry/exit is recorded from the start.
    * Drops the `show_args`/`show_return` toggles - both are always shown here. Arguments need the
      `call_seq` match spec (`ObserverWeb.Tracer.Tool.forced_match_spec_keys/1` forces it in), and
      return values come for free once `return_trace()` is set, so there's no extra cost to always
      including them.
    * `max_depth` is a fixed internal safety cap rather than an init option, to keep runaway
      recursion from growing a process's stack unbounded.
  """

  alias __MODULE__
  alias ObserverWeb.Tracer.Tool
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnFrom

  @max_depth 50

  @type t :: %__MODULE__{
          stacks: %{optional(pid()) => list()},
          depth: %{optional(pid()) => integer()}
        }

  defstruct stacks: %{}, depth: %{}

  @spec new :: t()
  def new, do: %CallSeq{}

  @spec handle_event(t(), struct()) :: t()
  def handle_event(%CallSeq{} = state, %EventCall{
        pid: pid,
        mod: mod,
        fun: fun,
        arity: arity,
        message: message
      }) do
    push_to_stack(state, pid, {:enter, mod, fun, arity, message})
  end

  def handle_event(%CallSeq{} = state, %EventReturnFrom{
        pid: pid,
        mod: mod,
        fun: fun,
        arity: arity,
        return_value: return_value
      }) do
    push_to_stack(state, pid, {:exit, mod, fun, arity, return_value})
  end

  def handle_event(state, _event), do: state

  # Collapses immediate self-recursion: if the top of the stack is already the same direction
  # (enter/exit) and {mod, fun, arity}, skip - this keeps deeply recursive calls from producing
  # one line per recursion level, matching how ObserverWeb.Tracer.Tool.Duration collapses
  # recursive durations to the outermost call.
  defp push_to_stack(%CallSeq{} = state, pid, {:enter, mod, fun, arity, _} = frame) do
    case top(state, pid) do
      {:enter, ^mod, ^fun, ^arity, _} -> state
      _ -> state |> append_if_below(pid, frame, @max_depth) |> increase_depth(pid, 1)
    end
  end

  defp push_to_stack(%CallSeq{} = state, pid, {:exit, mod, fun, arity, _} = frame) do
    case top(state, pid) do
      {:exit, ^mod, ^fun, ^arity, _} -> state
      _ -> state |> append_if_below(pid, frame, @max_depth + 1) |> increase_depth(pid, -1)
    end
  end

  defp top(%CallSeq{stacks: stacks}, pid) do
    case Map.get(stacks, pid, []) do
      [frame | _] -> frame
      [] -> nil
    end
  end

  defp append_if_below(%CallSeq{stacks: stacks, depth: depth} = state, pid, frame, threshold) do
    if Map.get(depth, pid, 0) < threshold do
      %{state | stacks: Map.update(stacks, pid, [frame], &[frame | &1])}
    else
      state
    end
  end

  defp increase_depth(%CallSeq{depth: depth} = state, pid, incr) do
    %{state | depth: Map.update(depth, pid, incr, &(&1 + incr))}
  end

  @doc """
  Finalizes into a flat, ordered list of `%{node:, pid:, pid_label:, depth:, type:, mod:, fun:,
  arity:, detail:}` maps - `detail` holds the call arguments on `:enter` and the return value on
  `:exit`, and `pid_label` is the process's registered name when it has one (see
  `ObserverWeb.Tracer.Tool.process_label/1`), the pid otherwise. Depth here is recomputed fresh
  per pid from the (already max-depth-capped) stack, so it's always a valid 0-based nesting level
  regardless of how deep the untruncated call actually went.
  """
  @spec handle_stop(t()) :: [map()]
  def handle_stop(%CallSeq{stacks: stacks}) do
    Enum.flat_map(stacks, fn {pid, stack} ->
      node = node(pid)
      pid_label = Tool.process_label(pid)

      stack
      |> Enum.reverse()
      |> Enum.map_reduce(0, fn
        {:enter, mod, fun, arity, message}, depth ->
          entry = %{
            node: node,
            pid: pid,
            pid_label: pid_label,
            depth: depth,
            type: :enter,
            mod: mod,
            fun: fun,
            arity: arity,
            detail: message
          }

          {entry, depth + 1}

        {:exit, mod, fun, arity, return_value}, depth ->
          # Clamped at 0: a session can start between a call and its return, so the very first
          # recorded event for a process may be an :exit with no matching :enter - without the
          # clamp that would emit a negative depth (and invalid negative CSS padding in the UI).
          depth = max(depth - 1, 0)

          entry = %{
            node: node,
            pid: pid,
            pid_label: pid_label,
            depth: depth,
            type: :exit,
            mod: mod,
            fun: fun,
            arity: arity,
            detail: return_value
          }

          {entry, depth}
      end)
      |> elem(0)
    end)
  end
end
