defmodule ObserverWeb.Tracer.Tool.FlameGraphTest do
  use ExUnit.Case, async: true

  import Mox

  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnTo
  alias ObserverWeb.Tracer.Tool.FlameGraph

  setup :verify_on_exit!

  # handle_stop/1 resolves process labels through Rpc.pinfo (see Tool.process_label/1).
  setup do
    stub(ObserverWeb.RpcMock, :pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)
    :ok
  end

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
    # A plain spawned process: no registered name, process label or proc_lib initial call, so the
    # root falls back to the inspected pid (the ExUnit test process would resolve to the process
    # label ExUnit sets on it).
    test_pid = self()

    pid =
      spawn(fn ->
        send(test_pid, :ready)

        receive do
          :done -> :ok
        end
      end)

    assert_receive :ready

    state =
      FlameGraph.new()
      |> FlameGraph.handle_event(call(String, :split, 2, {0, 0, 0}, pid))
      |> FlameGraph.handle_event(call(String, :split, 2, {0, 0, 100}, pid))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 250}, pid))

    assert [%{name: name, value: 250, children: children}] = FlameGraph.handle_stop(state)
    assert name == "#{inspect(pid)} (#{Node.self()})"
    assert [%{name: "String.split/2", value: 250, children: []}] = children

    send(pid, :done)
  end

  test "names the root after the process's registered name when it has one" do
    pid = self()
    Process.register(pid, :flame_graph_label_test)

    state =
      FlameGraph.new()
      |> FlameGraph.handle_event(call(String, :split, 2, {0, 0, 0}, pid))
      |> FlameGraph.handle_event(return_to(:undefined, :undefined, 0, {0, 0, 250}, pid))

    assert [%{name: name}] = FlameGraph.handle_stop(state)
    assert name == ":flame_graph_label_test (#{Node.self()})"
  after
    Process.unregister(:flame_graph_label_test)
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
