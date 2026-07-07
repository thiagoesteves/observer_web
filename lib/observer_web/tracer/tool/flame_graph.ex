defmodule ObserverWeb.Tracer.Tool.FlameGraph do
  @moduledoc """
  Tracks how much time each process spends in every call stack it goes through, and reports it as
  a plain `%{name:, value:, children:}` tree (one root per traced process) that the Profiling
  page renders as a flame graph client-side with the `FlameGraphEChart` hook (an ECharts custom
  series: one rect per call, width proportional to time spent, stacked under its caller).

  Ported and adapted from https://github.com/gabiz/tracer's `Tracer.Tool.FlameGraph`:

    * Unlike Count/Duration/CallSeq, this traces *every* call in the traced module(s) (no
      match-spec filtering) - a flame graph needs the full call graph to be meaningful. This is
      why `ObserverWeb.Tracer.Tool.dbg_flags/1` adds `:return_to` for this tool instead of a
      match-spec action: it unwinds the stack on return without needing `return_trace()` per
      function.
    * Drops upstream's synthetic `"sleep"` frame (driven by the `:running` trace flag's `:in`/`:out`
      scheduling events). `ObserverWeb.Tracer.Server` enables trace flags for *all* processes on
      the node (`:dbg.p(:all, ...)`), not just the ones executing traced code - `:running` isn't
      scoped by a match spec at all, so turning it on here would generate scheduling events for
      every process in the whole VM, not just the one(s) calling into the traced module. That's
      both noisy and a real performance/safety risk on a live system, so this only tracks active
      call-stack time, not idle time.
    * Upstream shells out to a bundled Perl script and writes to `/tmp` to render a literal flame
      graph SVG. Rendering client-side with the echarts dependency the project already has means
      no external-process/filesystem dependency and no new JS packages.
    * Caps how deep a single process's stack is tracked (not user-configurable), to keep runaway
      recursion from growing memory unbounded.
  """

  alias __MODULE__
  alias ObserverWeb.Tracer.Tool
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnTo

  @max_depth 100

  @type t :: %__MODULE__{process_state: map()}

  defstruct process_state: %{}

  @spec new :: t()
  def new, do: %FlameGraph{}

  @spec handle_event(t(), struct()) :: t()
  def handle_event(%FlameGraph{process_state: process_state} = state, event) do
    case event_pid(event) do
      nil ->
        state

      pid ->
        proc_state = Map.get(process_state, pid, %{stack: [], stack_acc: [], last_ts: nil})
        new_proc_state = handle_event_for_process(event, proc_state)
        %{state | process_state: Map.put(process_state, pid, new_proc_state)}
    end
  end

  defp event_pid(%EventCall{pid: pid}), do: pid
  defp event_pid(%EventReturnTo{pid: pid}), do: pid
  defp event_pid(_event), do: nil

  defp handle_event_for_process(%EventCall{mod: mod, fun: fun, arity: arity, ts: ts}, state) do
    state
    |> report_stack(ts_to_us(ts))
    |> push_stack(frame_name(mod, fun, arity))
  end

  # `:return_to` almost always reports the real calling function, whether or not it's itself
  # traced (only genuinely exceptional returns, e.g. into a BIF, come back as `:undefined`) -
  # since only the traced module's own calls are ever pushed, the common case is a caller frame
  # that was never pushed at all. pop_stack_to/2 treats "not found" the same as ":undefined": the
  # whole tracked stack is done.
  defp handle_event_for_process(
         %EventReturnTo{mod: mod, fun: fun, arity: arity, ts: ts},
         state
       ) do
    state
    |> report_stack(ts_to_us(ts))
    |> pop_stack_to(frame_name(mod, fun, arity))
  end

  defp frame_name(mod, fun, arity), do: "#{inspect(mod)}.#{fun}/#{arity}"

  # The very first event for a process only starts the clock - there's nothing to attribute time
  # to yet.
  defp report_stack(%{last_ts: nil} = state, ts), do: %{state | last_ts: ts}

  defp report_stack(
         %{stack: stack, stack_acc: [{stack, time} | rest], last_ts: last_ts} = state,
         ts
       ) do
    %{state | stack_acc: [{stack, time + (ts - last_ts)} | rest], last_ts: ts}
  end

  defp report_stack(%{stack: stack, stack_acc: stack_acc, last_ts: last_ts} = state, ts) do
    %{state | stack_acc: [{stack, ts - last_ts} | stack_acc], last_ts: ts}
  end

  defp push_stack(%{stack: [top | _rest]} = state, top), do: state

  defp push_stack(%{stack: stack} = state, _entry) when length(stack) >= @max_depth, do: state

  defp push_stack(%{stack: stack} = state, entry), do: %{state | stack: [entry | stack]}

  # If the target frame isn't found (the common case: `:return_to` names the real, untraced
  # caller), there's nothing left of the tracked stack to unwind to.
  defp pop_stack_to(%{stack: stack} = state, entry) do
    case Enum.drop_while(stack, &(&1 != entry)) do
      [] -> %{state | stack: []}
      new_stack -> %{state | stack: new_stack}
    end
  end

  defp ts_to_us({mega, seconds, micro}), do: (mega * 1_000_000 + seconds) * 1_000_000 + micro

  @doc """
  Finalizes into a list of chart-ready root nodes, one per traced process (`%{name:, value:,
  children:}`), sorted by total time descending. Processes with no completed samples are dropped.
  Roots are named by the process's registered name when it has one (see
  `ObserverWeb.Tracer.Tool.process_label/1`), the pid otherwise.
  """
  @spec handle_stop(t()) :: [map()]
  def handle_stop(%FlameGraph{process_state: process_state}) do
    process_state
    |> Enum.map(fn {pid, %{stack_acc: stack_acc}} ->
      children =
        stack_acc
        |> collapse_stacks()
        |> build_tree()

      %{
        name: "#{Tool.process_label(pid)} (#{node(pid)})",
        value: sum_values(children),
        children: children
      }
    end)
    |> Enum.reject(&(&1.value == 0))
    |> Enum.sort_by(& &1.value, :desc)
  end

  defp collapse_stacks(stack_acc) do
    Enum.reduce(stack_acc, %{}, fn {stack, time}, acc ->
      Map.update(acc, stack, time, &(&1 + time))
    end)
  end

  defp build_tree(collapsed_samples) do
    collapsed_samples
    |> Enum.reduce(%{}, fn {stack, time}, tree -> insert(tree, Enum.reverse(stack), time) end)
    |> to_nodes()
  end

  defp insert(tree, [], _time), do: tree

  defp insert(tree, [frame | rest], time) do
    {value, children} = Map.get(tree, frame, {0, %{}})
    Map.put(tree, frame, {value + time, insert(children, rest, time)})
  end

  defp to_nodes(tree) do
    tree
    |> Enum.map(fn {name, {value, children}} ->
      %{name: name, value: value, children: to_nodes(children)}
    end)
    |> Enum.sort_by(& &1.value, :desc)
  end

  defp sum_values(nodes), do: Enum.sum(Enum.map(nodes, & &1.value))
end
