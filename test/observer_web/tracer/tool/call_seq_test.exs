defmodule ObserverWeb.Tracer.Tool.CallSeqTest do
  use ExUnit.Case, async: true

  import Mox

  alias ObserverWeb.Tracer.Tool.CallSeq
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventIn
  alias ObserverWeb.Tracer.Tool.EventReturnFrom

  setup :verify_on_exit!

  # handle_stop/1 resolves process labels through Rpc.pinfo (see Tool.process_label/1).
  setup do
    stub(ObserverWeb.RpcMock, :pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)
    :ok
  end

  defp call(mod, fun, arity, pid, message \\ nil) do
    %EventCall{
      mod: mod,
      fun: fun,
      arity: arity,
      pid: pid,
      message: message,
      ts: :erlang.timestamp()
    }
  end

  defp return_from(mod, fun, arity, pid, return_value \\ nil) do
    %EventReturnFrom{
      mod: mod,
      fun: fun,
      arity: arity,
      pid: pid,
      return_value: return_value,
      ts: :erlang.timestamp()
    }
  end

  test "new/0 starts empty" do
    assert CallSeq.new() == %CallSeq{stacks: %{}, depth: %{}}
  end

  test "a single call/return pair is reported at depth 0" do
    pid = self()
    node = Node.self()

    state =
      CallSeq.new()
      |> CallSeq.handle_event(call(String, :split, 2, pid, [" ", "a b"]))
      |> CallSeq.handle_event(return_from(String, :split, 2, pid, ["a", "b"]))

    assert CallSeq.handle_stop(state) == [
             %{
               node: node,
               pid: pid,
               pid_label: inspect(pid),
               depth: 0,
               type: :enter,
               mod: String,
               fun: :split,
               arity: 2,
               detail: [" ", "a b"]
             },
             %{
               node: node,
               pid: pid,
               pid_label: inspect(pid),
               depth: 0,
               type: :exit,
               mod: String,
               fun: :split,
               arity: 2,
               detail: ["a", "b"]
             }
           ]
  end

  test "labels entries with the process's registered name when it has one" do
    pid = self()
    Process.register(pid, :call_seq_label_test)

    state =
      CallSeq.new()
      |> CallSeq.handle_event(call(String, :split, 2, pid))
      |> CallSeq.handle_event(return_from(String, :split, 2, pid))

    assert [%{pid_label: ":call_seq_label_test"} | _rest] = CallSeq.handle_stop(state)
  after
    Process.unregister(:call_seq_label_test)
  end

  test "nested calls increase depth and unwind back down on exit" do
    pid = self()

    state =
      CallSeq.new()
      |> CallSeq.handle_event(call(A, :outer, 0, pid))
      |> CallSeq.handle_event(call(B, :inner, 0, pid))
      |> CallSeq.handle_event(return_from(B, :inner, 0, pid))
      |> CallSeq.handle_event(return_from(A, :outer, 0, pid))

    assert [
             %{type: :enter, mod: A, fun: :outer, depth: 0},
             %{type: :enter, mod: B, fun: :inner, depth: 1},
             %{type: :exit, mod: B, fun: :inner, depth: 1},
             %{type: :exit, mod: A, fun: :outer, depth: 0}
           ] = Enum.map(CallSeq.handle_stop(state), &Map.take(&1, [:type, :mod, :fun, :depth]))
  end

  test "collapses direct recursion to a single enter/exit pair" do
    pid = self()

    state =
      CallSeq.new()
      |> CallSeq.handle_event(call(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(call(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(call(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(return_from(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(return_from(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(return_from(Recur, :fact, 1, pid))

    assert [
             %{type: :enter, mod: Recur, fun: :fact, depth: 0},
             %{type: :exit, mod: Recur, fun: :fact, depth: 0}
           ] = Enum.map(CallSeq.handle_stop(state), &Map.take(&1, [:type, :mod, :fun, :depth]))
  end

  test "the collapse check only looks at the immediate stack top, like upstream" do
    pid = self()

    # A second, non-adjacent `fact` call still collapses against its own immediately-preceding
    # exit once one comes right before it on the stack - this mirrors tracer's own
    # `push_to_stack_if_started/3`, which only ever inspects the top frame, not full history.
    state =
      CallSeq.new()
      |> CallSeq.handle_event(call(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(call(Other, :helper, 0, pid))
      |> CallSeq.handle_event(return_from(Other, :helper, 0, pid))
      |> CallSeq.handle_event(call(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(return_from(Recur, :fact, 1, pid))
      |> CallSeq.handle_event(return_from(Recur, :fact, 1, pid))

    assert [
             %{type: :enter, mod: Recur, fun: :fact},
             %{type: :enter, mod: Other, fun: :helper},
             %{type: :exit, mod: Other, fun: :helper},
             %{type: :enter, mod: Recur, fun: :fact},
             %{type: :exit, mod: Recur, fun: :fact}
           ] = Enum.map(CallSeq.handle_stop(state), &Map.take(&1, [:type, :mod, :fun]))
  end

  test "tracks separate stacks per process" do
    pid_a = spawn(fn -> :ok end)
    pid_b = spawn(fn -> :ok end)

    state =
      CallSeq.new()
      |> CallSeq.handle_event(call(String, :split, 2, pid_a))
      |> CallSeq.handle_event(call(Enum, :map, 2, pid_b))
      |> CallSeq.handle_event(return_from(String, :split, 2, pid_a))
      |> CallSeq.handle_event(return_from(Enum, :map, 2, pid_b))

    result = CallSeq.handle_stop(state)

    assert Enum.count(result, &(&1.pid == pid_a)) == 2
    assert Enum.count(result, &(&1.pid == pid_b)) == 2
  end

  test "ignores events other than call/return_from" do
    state = CallSeq.handle_event(CallSeq.new(), %EventIn{})

    assert CallSeq.handle_stop(state) == []
  end

  test "caps how deep the recorded stack grows, but keeps depth accounting balanced" do
    pid = self()

    modules = for i <- 1..60, do: Module.concat(Recur, "M#{i}")

    state =
      Enum.reduce(modules, CallSeq.new(), fn mod, state ->
        CallSeq.handle_event(state, call(mod, :f, 0, pid))
      end)

    state =
      Enum.reduce(Enum.reverse(modules), state, fn mod, state ->
        CallSeq.handle_event(state, return_from(mod, :f, 0, pid))
      end)

    result = CallSeq.handle_stop(state)

    # Not every one of the 60 nested enter/exit pairs made it in (capped), but every recorded
    # enter still has a matching recorded exit and depths never go negative.
    assert length(result) < 120
    assert Enum.all?(result, &(&1.depth >= 0))
    assert Enum.count(result, &(&1.type == :enter)) == Enum.count(result, &(&1.type == :exit))
  end
end
