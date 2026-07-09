defmodule ObserverWeb.SystemInfoTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.SystemInfo

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    :ok
  end

  describe "node_info/1" do
    test "collects runtime information from the local node" do
      assert {:ok, info} = SystemInfo.node_info(Node.self())

      assert info.otp_release == to_string(:erlang.system_info(:otp_release))
      assert info.erts_version == to_string(:erlang.system_info(:version))
      assert info.system_architecture != ""
      assert is_integer(info.schedulers)
      assert info.schedulers_online <= info.schedulers
      assert info.uptime_ms > 0
    end

    test "reports rpc failures as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert {:error, {:badrpc, :nodedown}} = SystemInfo.node_info(:unreachable@nohost)
    end
  end

  test "limits/1 reports every resource count against its VM limit" do
    limits = SystemInfo.limits(Node.self())

    assert Enum.map(limits, & &1.name) == ["Processes", "Ports", "Atoms", "ETS Tables"]

    Enum.each(limits, fn %{count: count, limit: limit, percent: percent} ->
      assert count > 0
      assert limit >= count
      # A tiny count against a huge limit legitimately rounds to 0.0%
      assert percent >= 0.0 and percent <= 100.0
    end)
  end

  test "allocators/1 reports carrier utilization for every alloc_util allocator" do
    allocators = SystemInfo.allocators(Node.self())

    assert allocators != []
    assert Enum.any?(allocators, &(&1.name == :binary_alloc))

    Enum.each(allocators, fn %{blocks_size: blocks, carriers_size: carriers} = alloc ->
      assert blocks >= 0
      assert carriers >= blocks

      if alloc.utilization_percent do
        assert alloc.utilization_percent >= 0.0 and alloc.utilization_percent <= 100.0
      end
    end)

    # Sorted by carrier size descending
    carrier_sizes = Enum.map(allocators, & &1.carriers_size)
    assert carrier_sizes == Enum.sort(carrier_sizes, :desc)
  end

  describe "allocator_utilization/2" do
    test "sums block and carrier sizes across instances and carrier types" do
      instances = [
        {:instance, 0,
         [
           mbcs: [
             {:blocks, [binary_alloc: [{:size, 100, 200, 300}]]},
             {:carriers_size, 400, 500, 600}
           ],
           sbcs: [
             {:blocks, [binary_alloc: [{:size, 50, 60, 70}]]},
             {:carriers_size, 100, 110, 120}
           ]
         ]},
        {:instance, 1,
         [
           mbcs: [{:blocks, [binary_alloc: [{:size, 25, 30, 35}]]}, {:carriers_size, 100, 0, 0}],
           sbcs: [{:blocks, []}, {:carriers_size, 0, 0, 0}]
         ]}
      ]

      assert %{
               name: :binary_alloc,
               blocks_size: 175,
               carriers_size: 600,
               utilization_percent: 29.17
             } = SystemInfo.allocator_utilization(:binary_alloc, instances)
    end

    test "supports the two-element size tuples some emulator types report" do
      instances = [
        {:instance, 0,
         [mbcs: [{:blocks, [test_alloc: [{:size, 10}]]}, {:carriers_size, 40}], sbcs: []]}
      ]

      assert %{blocks_size: 10, carriers_size: 40, utilization_percent: 25.0} =
               SystemInfo.allocator_utilization(:test_alloc, instances)
    end

    test "skips unexpected shapes instead of crashing" do
      instances = [
        {:instance, 0, [mbcs: [{:blocks, :unexpected}, {:carriers_size, :bad}], other: []]},
        :garbage,
        {:instance, 1, :not_a_list}
      ]

      assert %{blocks_size: 0, carriers_size: 0, utilization_percent: nil} =
               SystemInfo.allocator_utilization(:weird_alloc, instances)
    end
  end
end
