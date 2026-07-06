defmodule ObserverWeb.Tracer.ToolTest do
  use ExUnit.Case, async: true

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
  end

  describe "forced_match_spec_keys/1" do
    test "duration forces return_trace to see :return_from events" do
      assert Tool.forced_match_spec_keys(:duration) == ["return_trace"]
    end

    test "call_seq forces the combined call_seq match spec (return_trace + argument capture)" do
      assert Tool.forced_match_spec_keys(:call_seq) == ["call_seq"]
    end

    test "count and display force nothing" do
      assert Tool.forced_match_spec_keys(:count) == []
      assert Tool.forced_match_spec_keys(:display) == []
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

    test "falls back to a generic Event for anything else" do
      assert %Event{event: :something_unexpected} = Tool.from_trace(:something_unexpected)
    end
  end
end
