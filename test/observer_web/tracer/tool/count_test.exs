defmodule ObserverWeb.Tracer.Tool.CountTest do
  use ExUnit.Case, async: true

  alias ObserverWeb.Tracer.Tool.Count
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnFrom

  test "new/0 starts with no counts" do
    assert Count.new() == %Count{counts: %{}}
  end

  test "handle_event/2 tallies calls by mod/fun/arity" do
    event = %EventCall{mod: String, fun: :split, arity: 2, pid: self(), ts: :erlang.timestamp()}

    state =
      Count.new()
      |> Count.handle_event(event)
      |> Count.handle_event(event)

    assert Count.handle_stop(state) == [{{Node.self(), String, :split, 2, nil}, 2}]
  end

  test "handle_event/2 keeps distinct message content as separate keys" do
    # The `caller` match spec produces the calling pid as a raw message term (not a [name, value]
    # pair list - that shape is specific to tracer's own Matcher DSL, which isn't ported).
    ts = :erlang.timestamp()
    other_pid = spawn(fn -> :ok end)

    call_a = %EventCall{mod: String, fun: :split, arity: 2, pid: self(), message: self(), ts: ts}

    call_b = %EventCall{
      mod: String,
      fun: :split,
      arity: 2,
      pid: self(),
      message: other_pid,
      ts: ts
    }

    state =
      Count.new()
      |> Count.handle_event(call_a)
      |> Count.handle_event(call_a)
      |> Count.handle_event(call_b)

    result = Count.handle_stop(state)

    assert {{Node.self(), String, :split, 2, inspect(self())}, 2} in result
    assert {{Node.self(), String, :split, 2, inspect(other_pid)}, 1} in result
  end

  test "handle_event/2 ignores non-call events" do
    event = %EventReturnFrom{
      mod: String,
      fun: :split,
      arity: 2,
      pid: self(),
      return_value: [],
      ts: :erlang.timestamp()
    }

    assert Count.new() |> Count.handle_event(event) |> Count.handle_stop() == []
  end

  test "handle_stop/1 sorts by count descending" do
    ts = :erlang.timestamp()
    frequent = %EventCall{mod: CountTestModA, fun: :f, arity: 0, pid: self(), ts: ts}
    rare = %EventCall{mod: CountTestModB, fun: :g, arity: 0, pid: self(), ts: ts}

    state =
      Count.new()
      |> Count.handle_event(frequent)
      |> Count.handle_event(frequent)
      |> Count.handle_event(frequent)
      |> Count.handle_event(rare)

    assert [
             {{Node.self(), CountTestModA, :f, 0, nil}, 3},
             {{Node.self(), CountTestModB, :g, 0, nil}, 1}
           ] ==
             Count.handle_stop(state)
  end
end
