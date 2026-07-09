defmodule ObserverWeb.ProcessesTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Processes

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    stub(ObserverWeb.RpcMock, :pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    :ok
  end

  describe "sample/2" do
    test "collects every process on the local node with its metrics" do
      Process.register(self(), :processes_sample_label_test)

      assert {:ok, %{node: node, process_count: process_count, processes: processes} = sample} =
               Processes.sample()

      assert node == Node.self()
      assert process_count > 0
      assert process_count == length(processes)
      assert is_integer(sample.run_queue)
      assert %{total: total} = sample.memory
      assert total > 0

      assert %{memory: memory, reductions: reds, message_queue_len: mq} =
               Enum.find(processes, &(&1.name == ":processes_sample_label_test"))

      assert memory > 0
      assert reds > 0
      assert mq >= 0
    after
      Process.unregister(:processes_sample_label_test)
    end

    test "labels unregistered processes by their initial call or process label" do
      test_pid = self()

      pid =
        spawn(fn ->
          send(test_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready

      assert {:ok, %{processes: processes}} = Processes.sample()

      assert %{name: name} = Enum.find(processes, &(&1.pid == pid))
      assert is_binary(name)
      assert name != ""

      send(pid, :done)
    end

    test "reports rpc failures as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert {:error, :nodedown} = Processes.sample(:unreachable@nohost)
    end

    test "reports unexpected replies as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        :unexpected
      end)

      assert {:error, {:unexpected_reply, :unexpected}} = Processes.sample(Node.self())
    end

    test "times out when the collector never reports back" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout -> :ok end)

      assert {:error, :timeout} = Processes.sample(Node.self(), 10)
    end
  end

  describe "rank/4" do
    defp row(pid, memory, reductions, mq) do
      %{
        pid: pid,
        name: inspect(pid),
        memory: memory,
        reductions: reductions,
        reductions_diff: reductions,
        message_queue_len: mq,
        current_function: "Mod.fun/1"
      }
    end

    test "ranks by memory and caps at the limit" do
      pids = [:a, :b, :c]
      sample = %{processes: [row(:a, 10, 0, 0), row(:b, 30, 0, 0), row(:c, 20, 0, 0)]}

      assert [%{pid: :b}, %{pid: :c}] = Processes.rank(sample, :memory, 2)
      assert length(Processes.rank(sample, :memory, 10)) == length(pids)
    end

    test "ranks by message queue length" do
      sample = %{processes: [row(:a, 0, 0, 5), row(:b, 0, 0, 50)]}

      assert [%{pid: :b}, %{pid: :a}] = Processes.rank(sample, :message_queue_len, 10)
    end

    test "ranks reductions by the delta from the previous sample" do
      sample = %{processes: [row(:a, 0, 1_000, 0), row(:b, 0, 900, 0)]}

      # :a did 1000 - 990 = 10 since last sample, :b did 900 - 0 = 900
      previous = %{a: 990}

      assert [%{pid: :b, reductions_diff: 900}, %{pid: :a, reductions_diff: 10}] =
               Processes.rank(sample, :reductions, 10, previous)
    end

    test "first sample ranks by cumulative reductions" do
      sample = %{processes: [row(:a, 0, 100, 0), row(:b, 0, 200, 0)]}

      assert [%{pid: :b, reductions_diff: 200}, %{pid: :a, reductions_diff: 100}] =
               Processes.rank(sample, :reductions, 10, %{})
    end
  end

  test "reductions_by_pid/1 maps pids to their cumulative reductions" do
    sample = %{processes: [row(:a, 0, 100, 0), row(:b, 0, 200, 0)]}

    assert Processes.reductions_by_pid(sample) == %{a: 100, b: 200}
  end

  describe "details/1" do
    test "returns display-ready pairs for a live process" do
      assert {:ok, info} = Processes.details(self())

      keys = Enum.map(info, &elem(&1, 0))
      assert "status" in keys
      assert "memory" in keys
      assert "current stacktrace" in keys

      assert Enum.all?(info, fn {_key, value} -> is_binary(value) end)
    end

    test "returns not_found for a dead process" do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert {:error, :not_found} = Processes.details(pid)
    end
  end
end
