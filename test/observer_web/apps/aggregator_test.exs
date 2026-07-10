defmodule ObserverWeb.Apps.AggregatorTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Apps
  alias ObserverWeb.Apps.Aggregator

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    stub(ObserverWeb.RpcMock, :pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    :ok
  end

  defp tree_node(id, children \\ []) do
    %Apps{id: id, children: children}
  end

  describe "count/1" do
    test "counts processes, ports and references across the whole tree" do
      port = Port.open({:spawn, "cat"}, [:binary])
      ref = make_ref()

      tree =
        tree_node(self(), [
          tree_node(port, [tree_node(ref)]),
          tree_node(spawn(fn -> :ok end))
        ])

      assert Aggregator.count(tree) == %{processes: 2, ports: 1, references: 1}

      Port.close(port)
    end

    test "counts a real application tree" do
      tree = Apps.info(Node.self(), :kernel)

      counts = Aggregator.count(tree)
      assert counts.processes > 10
      assert counts.references >= 0
    end
  end

  describe "stats/1" do
    test "sums memory, reductions and message queue over live processes" do
      tree = tree_node(self(), [tree_node(spawn(fn -> Process.sleep(:infinity) end))])

      stats = Aggregator.stats(tree)

      assert stats.sampled == 2
      assert stats.memory > 0
      assert stats.reductions > 0
      assert stats.message_queue_len >= 0
      refute stats.partial?
    end

    test "skips processes that died since the tree was built" do
      dead = spawn(fn -> :ok end)
      ref = Process.monitor(dead)
      assert_receive {:DOWN, ^ref, :process, ^dead, _reason}

      tree = tree_node(self(), [tree_node(dead)])

      stats = Aggregator.stats(tree)

      assert stats.sampled == 1
      refute stats.partial?
    end

    test "ignores non-pid ids and deduplicates repeated pids" do
      port = Port.open({:spawn, "cat"}, [:binary])

      tree = tree_node(self(), [tree_node(port), tree_node(self())])

      assert %{sampled: 1} = Aggregator.stats(tree)

      Port.close(port)
    end

    test "caps sampling and flags the result as partial for oversized trees" do
      pids = for _i <- 1..2_001, do: spawn(fn -> Process.sleep(:infinity) end)

      tree = tree_node(self(), Enum.map(pids, &tree_node/1))

      stats = Aggregator.stats(tree)

      assert stats.partial?
      assert stats.sampled == 2_000

      Enum.each(pids, &Process.exit(&1, :kill))
    end

    test "sums a real application tree" do
      tree = Apps.info(Node.self(), :kernel)

      stats = Aggregator.stats(tree)

      assert stats.sampled > 10
      assert stats.memory > 100_000
      assert stats.reductions > 0
    end
  end
end
