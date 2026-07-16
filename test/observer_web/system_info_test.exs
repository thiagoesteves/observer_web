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

  describe "os_data/1" do
    test "reports an error when os_mon is not running" do
      Application.stop(:os_mon)

      assert {:error, :os_mon_not_started} = SystemInfo.os_data(Node.self())
    end

    test "reports rpc failures as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert {:error, {:badrpc, :nodedown}} = SystemInfo.os_data(:unreachable@nohost)
    end

    test "collects OS data from a running os_mon" do
      {:ok, _apps} = Application.ensure_all_started(:os_mon)
      on_exit(fn -> Application.stop(:os_mon) end)

      assert {:ok, os_data} = SystemInfo.os_data(Node.self())

      assert is_binary(os_data.os)
      assert is_list(os_data.cpus)
      assert is_list(os_data.disks)

      if os_data.load do
        assert os_data.load.avg1 >= 0.0
        assert os_data.load.avg5 >= 0.0
        assert os_data.load.avg15 >= 0.0
      end

      if os_data.memory do
        assert os_data.memory.total_bytes > 0
        assert os_data.memory.available_bytes <= os_data.memory.total_bytes
        assert os_data.memory.used_percent >= 0.0 and os_data.memory.used_percent <= 100.0
      end
    end

    test "normalizes every probe from stubbed rpc responses" do
      stub(ObserverWeb.RpcMock, :call, fn
        _node, :erlang, :whereis, [:os_mon_sup], _timeout -> self()
        _node, :os, :type, [], _timeout -> {:unix, :linux}
        _node, :os, :version, [], _timeout -> {6, 1, 0}
        _node, :cpu_sup, :avg1, [], _timeout -> 512
        _node, :cpu_sup, :avg5, [], _timeout -> 256
        _node, :cpu_sup, :avg15, [], _timeout -> 128
        _node, :cpu_sup, :util, [[:per_cpu]], _timeout -> [{0, 75.5, 24.5, []}, {1, 10, 90, []}]
        _node, :memsup, :get_system_memory_data, [], _timeout -> mem_data()
        _node, :disksup, :get_disk_data, [], _timeout -> [{~c"/", 1_000_000, 45}]
      end)

      assert {:ok, os_data} = SystemInfo.os_data(:fake@node)

      assert os_data.os == "unix/linux 6.1.0"
      assert os_data.load == %{avg1: 2.0, avg5: 1.0, avg15: 0.5}

      assert os_data.cpus == [
               %{id: 0, busy_percent: 75.5},
               %{id: 1, busy_percent: 10.0}
             ]

      assert os_data.memory == %{
               total_bytes: 1_000,
               available_bytes: 250,
               used_percent: 75.0
             }

      assert os_data.disks == [%{mount: "/", total_kbytes: 1_000_000, capacity_percent: 45}]
    end

    test "degrades each probe individually when unsupported" do
      stub(ObserverWeb.RpcMock, :call, fn
        _node, :erlang, :whereis, [:os_mon_sup], _timeout -> self()
        _node, :os, :type, [], _timeout -> {:badrpc, :nodedown}
        _node, :os, :version, [], _timeout -> {6, 1, 0}
        _node, :cpu_sup, :avg1, [], _timeout -> {:error, :not_supported}
        _node, :cpu_sup, :avg5, [], _timeout -> 256
        _node, :cpu_sup, :avg15, [], _timeout -> 128
        _node, :cpu_sup, :util, [[:per_cpu]], _timeout -> {:badrpc, {:EXIT, :noproc}}
        _node, :memsup, :get_system_memory_data, [], _timeout -> {:badrpc, {:EXIT, :noproc}}
        _node, :disksup, :get_disk_data, [], _timeout -> {:badrpc, {:EXIT, :noproc}}
      end)

      assert {:ok, os_data} = SystemInfo.os_data(:fake@node)

      assert os_data.os == nil
      assert os_data.load == nil
      assert os_data.cpus == []
      assert os_data.memory == nil
      assert os_data.disks == []
    end

    test "skips malformed cpu and disk entries and charlist os versions are supported" do
      stub(ObserverWeb.RpcMock, :call, fn
        _node, :erlang, :whereis, [:os_mon_sup], _timeout -> self()
        _node, :os, :type, [], _timeout -> {:win32, :nt}
        _node, :os, :version, [], _timeout -> ~c"10.0"
        _node, :cpu_sup, :avg1, [], _timeout -> 0
        _node, :cpu_sup, :avg5, [], _timeout -> 0
        _node, :cpu_sup, :avg15, [], _timeout -> 0
        _node, :cpu_sup, :util, [[:per_cpu]], _timeout -> [{0, :bad, 0, []}, :garbage]
        _node, :memsup, :get_system_memory_data, [], _timeout -> [free_memory: 10]
        _node, :disksup, :get_disk_data, [], _timeout -> [{~c"none", :na, 0}, :garbage]
      end)

      assert {:ok, os_data} = SystemInfo.os_data(:fake@node)

      assert os_data.os == "win32/nt 10.0"
      assert os_data.load == %{avg1: 0.0, avg5: 0.0, avg15: 0.0}
      assert os_data.cpus == []
      assert os_data.memory == nil
      assert os_data.disks == []
    end
  end

  defp mem_data do
    [
      system_total_memory: 1_000,
      total_memory: 900,
      available_memory: 250,
      free_memory: 100
    ]
  end
end
