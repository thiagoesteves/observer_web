defmodule ObserverWeb.Tracer.Tool.FlameGraphTest do
  use ExUnit.Case, async: true

  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnTo
  alias ObserverWeb.Tracer.Tool.FlameGraph

  defp call(mod, fun, arity, ts, pid),
    do: %EventCall{mod: mod, fun: fun, arity: arity, pid: pid, ts: ts}

  defp return_to(mod, fun, arity, ts, pid),
    do: %EventReturnTo{mod: mod, fun: fun, arity: arity, pid: pid, ts: ts}

  test "new/0 starts empty" do
    assert FlameGraph.new() == %FlameGraph{process_state: %{}}
  end

  test "processes with no completed samples are dropped" do
    state = FlameGraph.handle_event(FlameGraph.new(), call(String, :split, 2, {0, 0, 0}, self()))

    assert FlameGraph.handle_stop(state) == []
  end

  test "attributes time spent in a single frame" do
    pid = self()
    node = Node.self()

    state =
      FlameGraph.new()
      |> FlameGraph.handle_event(call(String, :split, 2, {0, 0, 0}, pid))
      |> FlameGraph.handle_event(call(String, :split, 2, {0, 0, 100}, pid))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 250}, pid))

    assert [%{name: name, value: 250, children: children}] = FlameGraph.handle_stop(state)
    assert name == "#{inspect(pid)} (#{node})"
    assert [%{name: "String.split/2", value: 250, children: []}] = children
  end

  test "builds a nested tree from a call/call/return_to/return_to sequence" do
    pid = self()

    state =
      FlameGraph.new()
      |> FlameGraph.handle_event(call(Outer, :run, 0, {0, 0, 0}, pid))
      |> FlameGraph.handle_event(call(Inner, :work, 0, {0, 0, 10}, pid))
      |> FlameGraph.handle_event(return_to(Outer, :run, 0, {0, 0, 40}, pid))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 60}, pid))

    assert [%{name: _, value: 60, children: children}] = FlameGraph.handle_stop(state)
    assert [%{name: "Outer.run/0", value: 60, children: inner_children}] = children
    assert [%{name: "Inner.work/0", value: 30, children: []}] = inner_children
  end

  test "collapses immediately repeated identical frames" do
    pid = self()

    state =
      FlameGraph.new()
      |> FlameGraph.handle_event(call(Recur, :fact, 1, {0, 0, 0}, pid))
      |> FlameGraph.handle_event(call(Recur, :fact, 1, {0, 0, 5}, pid))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 20}, pid))

    assert [%{value: 20, children: children}] = FlameGraph.handle_stop(state)
    assert [%{name: "Recur.fact/1", value: 20, children: []}] = children
  end

  test "tracks separate stacks per process" do
    pid_a = spawn(fn -> :ok end)
    pid_b = spawn(fn -> :ok end)

    state =
      FlameGraph.new()
      |> FlameGraph.handle_event(call(String, :split, 2, {0, 0, 0}, pid_a))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 10}, pid_a))
      |> FlameGraph.handle_event(call(Enum, :map, 2, {0, 0, 0}, pid_b))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 20}, pid_b))

    result = FlameGraph.handle_stop(state)

    assert length(result) == 2
    assert Enum.any?(result, &(&1.value == 10))
    assert Enum.any?(result, &(&1.value == 20))
  end

  test "ignores events without a pid" do
    state = FlameGraph.handle_event(FlameGraph.new(), %ObserverWeb.Tracer.Tool.Event{})

    assert FlameGraph.handle_stop(state) == []
  end
end
