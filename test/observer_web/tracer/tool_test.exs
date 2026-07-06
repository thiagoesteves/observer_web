defmodule ObserverWeb.Tracer.ToolTest do
  use ExUnit.Case, async: true

  alias ObserverWeb.Tracer.Tool
  alias ObserverWeb.Tracer.Tool.Count
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
  end

  describe "init/1, handle_event/3, handle_stop/2 for :count" do
    test "dispatches to ObserverWeb.Tracer.Tool.Count" do
      pid = self()
      ts = :erlang.timestamp()
      initial_state = Tool.init(:count)

      assert %Count{} = initial_state

      state =
        Tool.handle_event(:count, {:trace_ts, pid, :call, {String, :split, 2}, ts}, initial_state)

      assert Tool.handle_stop(:count, state) == [{{String, :split, 2, nil}, 1}]
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
