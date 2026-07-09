defmodule ObserverWeb.Tracer.ToolTest do
  use ExUnit.Case, async: true

  import Mox

  alias ObserverWeb.Tracer.Tool
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

  setup :verify_on_exit!

  # CallSeq's and FlameGraph's handle_stop resolve process labels through Rpc.pinfo (see
  # Tool.process_label/1).
  setup do
    stub(ObserverWeb.RpcMock, :pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)
    :ok
  end

  describe "process_label/1" do
    test "returns the registered name when the process has one" do
      Process.register(self(), :tool_process_label_test)

      assert Tool.process_label(self()) == ":tool_process_label_test"
    after
      Process.unregister(:tool_process_label_test)
    end

    test "falls back to the process label for unregistered processes that set one" do
      test_pid = self()

      pid =
        spawn(fn ->
          Process.set_label("tool label test")
          send(test_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready

      assert Tool.process_label(pid) == "tool label test"

      send(pid, :done)
    end

    test "falls back to the proc_lib initial call, suffixed with the pid" do
      {:ok, pid} = Task.start(fn -> Process.sleep(:infinity) end)

      label = Tool.process_label(pid)

      # proc_lib's :"$initial_call" for a Task is the anonymous function's generated module
      # (this test module), formatted as an MFA and suffixed with the pid.
      assert label =~ "ToolTest"
      assert String.ends_with?(label, inspect(pid))
      refute label == inspect(pid)

      Process.exit(pid, :kill)
    end

    test "falls back to the pid for plain spawned processes without any label" do
      test_pid = self()

      pid =
        spawn(fn ->
          send(test_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready

      assert Tool.process_label(pid) == inspect(pid)

      send(pid, :done)
    end

    test "falls back to the pid for dead processes" do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert Tool.process_label(pid) == inspect(pid)
    end
  end

  describe "dbg_flags/1" do
    test "display traces full argument values (no :arity flag)" do
      assert Tool.dbg_flags(:display) == [:c, :timestamp]
    end

    test "count requires :arity to aggregate by {mod, fun, arity} instead of argument values" do
      assert Tool.dbg_flags(:count) == [:c, :timestamp, :arity]
    end

    test "duration requires :arity for the same reason as count" do
      assert Tool.dbg_flags(:duration) == [:c, :timestamp, :arity]
    end

    test "call_seq requires :arity for the same reason as count" do
      assert Tool.dbg_flags(:call_seq) == [:c, :timestamp, :arity]
    end

    test "flame_graph additionally requires :return_to (but not :running - see FlameGraph)" do
      assert Tool.dbg_flags(:flame_graph) == [:c, :timestamp, :arity, :return_to]
    end
  end

  describe "forced_match_spec_keys/1" do
    test "duration forces return_trace to see :return_from events" do
      assert Tool.forced_match_spec_keys(:duration) == ["return_trace"]
    end

    test "call_seq forces the combined call_seq match spec (return_trace + argument capture)" do
      assert Tool.forced_match_spec_keys(:call_seq) == ["call_seq"]
    end

    test "count, display and flame_graph force nothing" do
      assert Tool.forced_match_spec_keys(:count) == []
      assert Tool.forced_match_spec_keys(:display) == []
      assert Tool.forced_match_spec_keys(:flame_graph) == []
    end
  end

  describe "init/2, handle_event/3, handle_stop/2 for :count" do
    test "dispatches to ObserverWeb.Tracer.Tool.Count" do
      pid = self()
      ts = :erlang.timestamp()
      initial_state = Tool.init(:count, %{})

      assert %Count{} = initial_state

      state =
        Tool.handle_event(:count, {:trace_ts, pid, :call, {String, :split, 2}, ts}, initial_state)

      assert Tool.handle_stop(:count, state) == [{{Node.self(), String, :split, 2, nil}, 1}]
    end
  end

  describe "init/2, handle_event/3, handle_stop/2 for :duration" do
    test "dispatches to ObserverWeb.Tracer.Tool.Duration, honoring tool_opts" do
      pid = self()
      initial_state = Tool.init(:duration, %{aggregation: :sum})

      assert %Duration{aggregation: :sum} = initial_state

      call_trace = {:trace_ts, pid, :call, {String, :split, 2}, {0, 0, 0}}
      return_trace = {:trace_ts, pid, :return_from, {String, :split, 2}, [], {0, 0, 10}}

      state = Tool.handle_event(:duration, call_trace, initial_state)
      state = Tool.handle_event(:duration, return_trace, state)

      assert Tool.handle_stop(:duration, state) == [{{Node.self(), String, :split, 2, nil}, 10}]
    end
  end

  describe "init/2, handle_event/3, handle_stop/2 for :call_seq" do
    test "dispatches to ObserverWeb.Tracer.Tool.CallSeq" do
      pid = self()
      initial_state = Tool.init(:call_seq, %{})

      assert %CallSeq{} = initial_state

      call_trace = {:trace_ts, pid, :call, {String, :split, 2}, ["a", "b"], {0, 0, 0}}
      return_trace = {:trace_ts, pid, :return_from, {String, :split, 2}, ["a"], {0, 0, 10}}

      state = Tool.handle_event(:call_seq, call_trace, initial_state)
      state = Tool.handle_event(:call_seq, return_trace, state)

      assert [
               %{type: :enter, mod: String, fun: :split, arity: 2, detail: ["a", "b"]},
               %{type: :exit, mod: String, fun: :split, arity: 2, detail: ["a"]}
             ] = Tool.handle_stop(:call_seq, state)
    end
  end

  describe "init/2, handle_event/3, handle_stop/2 for :flame_graph" do
    test "dispatches to ObserverWeb.Tracer.Tool.FlameGraph" do
      pid = self()
      initial_state = Tool.init(:flame_graph, %{})

      assert %FlameGraph{} = initial_state

      call_trace = {:trace_ts, pid, :call, {String, :split, 2}, {0, 0, 1}}
      return_to_trace = {:trace_ts, pid, :return_to, :undefined, {0, 0, 11}}

      state = Tool.handle_event(:flame_graph, call_trace, initial_state)
      state = Tool.handle_event(:flame_graph, return_to_trace, state)

      assert [%{value: 10, children: [%{name: "String.split/2", value: 10, children: []}]}] =
               Tool.handle_stop(:flame_graph, state)
    end
  end

  describe "from_trace/1" do
    test "translates a :call event with message" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventCall{
               mod: String,
               fun: :split,
               arity: 2,
               pid: ^pid,
               message: [[:a, 1]],
               ts: ^ts
             } =
               Tool.from_trace({:trace_ts, pid, :call, {String, :split, 2}, [[:a, 1]], ts})
    end

    test "translates a :call event without message" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventCall{mod: String, fun: :split, arity: 2, pid: ^pid, message: nil, ts: ^ts} =
               Tool.from_trace({:trace_ts, pid, :call, {String, :split, 2}, ts})
    end

    test "translates a :return_from event" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventReturnFrom{mod: String, fun: :split, arity: 2, pid: ^pid, return_value: []} =
               Tool.from_trace({:trace_ts, pid, :return_from, {String, :split, 2}, [], ts})
    end

    test "translates a :return_to event" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventReturnTo{mod: String, fun: :split, arity: 2, pid: ^pid} =
               Tool.from_trace({:trace_ts, pid, :return_to, {String, :split, 2}, ts})
    end

    test "translates an :undefined :return_to event" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventReturnTo{mod: :undefined, fun: :undefined, arity: 0, pid: ^pid} =
               Tool.from_trace({:trace_ts, pid, :return_to, :undefined, ts})
    end

    test "translates :in and :out scheduling events" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventIn{mod: String, fun: :split, arity: 2, pid: ^pid} =
               Tool.from_trace({:trace_ts, pid, :in, {String, :split, 2}, ts})

      assert %EventOut{mod: String, fun: :split, arity: 2, pid: ^pid} =
               Tool.from_trace({:trace_ts, pid, :out, {String, :split, 2}, ts})
    end

    test "translates :in and :out events with an unknown (0) MFA" do
      pid = self()
      ts = :erlang.timestamp()

      assert %EventIn{mod: :undefined, fun: :undefined, arity: 0, pid: ^pid} =
               Tool.from_trace({:trace_ts, pid, :in, 0, ts})

      assert %EventOut{mod: :undefined, fun: :undefined, arity: 0, pid: ^pid} =
               Tool.from_trace({:trace_ts, pid, :out, 0, ts})
    end

    test "falls back to a generic Event for anything else" do
      assert %Event{event: :something_unexpected} = Tool.from_trace(:something_unexpected)
    end
  end
end
