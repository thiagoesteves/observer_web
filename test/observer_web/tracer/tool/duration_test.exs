defmodule ObserverWeb.Tracer.Tool.DurationTest do
  use ExUnit.Case, async: true

  alias ObserverWeb.Tracer.Tool.Duration
  alias ObserverWeb.Tracer.Tool.EventCall
  alias ObserverWeb.Tracer.Tool.EventReturnFrom

  defp call(mod, fun, arity, ms, pid) do
    %EventCall{mod: mod, fun: fun, arity: arity, pid: pid, ts: ms_to_ts(ms)}
  end

  defp return_from(mod, fun, arity, ms, pid) do
    %EventReturnFrom{mod: mod, fun: fun, arity: arity, pid: pid, ts: ms_to_ts(ms)}
  end

  defp ms_to_ts(ms), do: {0, 0, ms}

  test "new/1 defaults to no aggregation" do
    assert Duration.new() == %Duration{
             aggregation: nil,
             stacks: %{},
             collect: Duration.new().collect
           }
  end

  test "measures the duration between a call and its matching return_from" do
    pid = self()
    node = Node.self()

    state =
      Duration.new()
      |> Duration.handle_event(call(String, :split, 2, 100, pid))
      |> Duration.handle_event(return_from(String, :split, 2, 140, pid))

    assert [{{^node, String, :split, 2, nil}, 40}] = Duration.handle_stop(state)
  end

  test "tracks separate stacks per process" do
    pid_a = spawn(fn -> :ok end)
    pid_b = spawn(fn -> :ok end)
    node = Node.self()

    state =
      Duration.new()
      |> Duration.handle_event(call(String, :split, 2, 0, pid_a))
      |> Duration.handle_event(call(String, :split, 2, 0, pid_b))
      |> Duration.handle_event(return_from(String, :split, 2, 10, pid_a))
      |> Duration.handle_event(return_from(String, :split, 2, 30, pid_b))

    result = Duration.handle_stop(state)

    assert {{node, String, :split, 2, nil}, 10} in result
    assert {{node, String, :split, 2, nil}, 30} in result
  end

  test "collapses direct recursion so the outermost call's duration is reported" do
    pid = self()
    node = Node.self()

    state =
      Duration.new()
      |> Duration.handle_event(call(Recur, :fact, 1, 0, pid))
      |> Duration.handle_event(call(Recur, :fact, 1, 10, pid))
      |> Duration.handle_event(return_from(Recur, :fact, 1, 20, pid))
      |> Duration.handle_event(return_from(Recur, :fact, 1, 30, pid))

    assert [{{^node, Recur, :fact, 1, nil}, 30}] = Duration.handle_stop(state)
  end

  test "ignores a return_from with no matching call on the stack" do
    pid = self()

    state = Duration.handle_event(Duration.new(), return_from(String, :split, 2, 10, pid))

    assert Duration.handle_stop(state) == []
  end

  test "ignores non call/return_from events" do
    state = Duration.handle_event(Duration.new(), %ObserverWeb.Tracer.Tool.EventIn{})

    assert Duration.handle_stop(state) == []
  end

  test "keeps distinct message content as separate keys" do
    pid = self()
    other_pid = spawn(fn -> :ok end)
    node = Node.self()

    state =
      Duration.new()
      |> Duration.handle_event(%EventCall{
        mod: String,
        fun: :split,
        arity: 2,
        pid: pid,
        message: pid,
        ts: ms_to_ts(0)
      })
      |> Duration.handle_event(return_from(String, :split, 2, 10, pid))
      |> Duration.handle_event(%EventCall{
        mod: String,
        fun: :split,
        arity: 2,
        pid: pid,
        message: other_pid,
        ts: ms_to_ts(0)
      })
      |> Duration.handle_event(return_from(String, :split, 2, 20, pid))

    result = Duration.handle_stop(state)

    assert {{node, String, :split, 2, inspect(pid)}, 10} in result
    assert {{node, String, :split, 2, inspect(other_pid)}, 20} in result
  end

  describe "aggregation modes" do
    setup do
      pid = self()

      state =
        Duration.new(%{aggregation: nil})
        |> Duration.handle_event(call(String, :split, 2, 0, pid))
        |> Duration.handle_event(return_from(String, :split, 2, 10, pid))
        |> Duration.handle_event(call(String, :split, 2, 0, pid))
        |> Duration.handle_event(return_from(String, :split, 2, 30, pid))
        |> Duration.handle_event(call(String, :split, 2, 0, pid))
        |> Duration.handle_event(return_from(String, :split, 2, 20, pid))

      {:ok, state: state, node: Node.self()}
    end

    test "no aggregation reports every individual sample", %{state: state} do
      result = Duration.handle_stop(%{state | aggregation: nil})
      assert Enum.sort(Enum.map(result, &elem(&1, 1))) == [10, 20, 30]
    end

    test ":sum adds every sample for the key", %{state: state, node: node} do
      assert [{{^node, String, :split, 2, nil}, 60}] =
               Duration.handle_stop(%{state | aggregation: :sum})
    end

    test ":avg averages every sample for the key", %{state: state, node: node} do
      assert [{{^node, String, :split, 2, nil}, 20.0}] =
               Duration.handle_stop(%{state | aggregation: :avg})
    end

    test ":min picks the smallest sample for the key", %{state: state, node: node} do
      assert [{{^node, String, :split, 2, nil}, 10}] =
               Duration.handle_stop(%{state | aggregation: :min})
    end

    test ":max picks the largest sample for the key", %{state: state, node: node} do
      assert [{{^node, String, :split, 2, nil}, 30}] =
               Duration.handle_stop(%{state | aggregation: :max})
    end

    test ":dist buckets samples into a power-of-two histogram", %{state: state, node: node} do
      assert [{{^node, String, :split, 2, nil}, histogram}] =
               Duration.handle_stop(%{state | aggregation: :dist})

      assert is_map(histogram)
      assert Enum.sum(Map.values(histogram)) == 3
    end
  end
end
