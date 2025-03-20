defmodule ObserverWeb.LocalStorageTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  alias ObserverWeb.Telemetry.Storage
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :create_consumer,
    :metric_table
  ]

  test "[un]subscribe_for_new_keys/0", %{node: node, metric_table: metric_table} do
    Storage.subscribe_for_new_keys()

    ObserverWeb.RpcMock
    |> stub(:call, fn ^node, :ets, :lookup, [^metric_table, "metric-keys"], :infinity ->
      [{"metric-keys", []}]
    end)

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:metrics_new_keys, ^node, ["vm.memory.total"]}, 1_000
  end

  test "[un]subscribe_for_new_data/0", %{node: node, metric_table: metric_table} do
    Storage.subscribe_for_new_data(node, "vm.memory.total")

    ObserverWeb.RpcMock
    |> stub(:call, fn ^node, :ets, :lookup, [^metric_table, "metric-keys"], :infinity ->
      [{"metric-keys", []}]
    end)

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:metrics_new_data, ^node, "vm.memory.total",
                    %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: _, measurements: _}},
                   1_000

    # Validate by inspection
    Storage.unsubscribe_for_new_data(node, "vm.memory.total")
  end

  test "get_keys_by_node/1 valid node", %{node: node, metric_table: metric_table} do
    Storage.subscribe_for_new_data(node, "vm.memory.total")
    test_pid = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn ^node, :ets, :lookup, [^metric_table, "metric-keys"], :infinity ->
      if test_pid != self() do
        # GenServer Cast
        [{"metric-keys", []}]
      else
        # Reading Ets directly
        [{"metric-keys", ["vm.memory.total"]}]
      end
    end)

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:metrics_new_data, ^node, "vm.memory.total",
                    %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: _, measurements: _}},
                   1_000

    assert ["vm.memory.total"] == Storage.get_keys_by_node(node)
  end

  test "node/1 invalid node" do
    assert [] == Storage.get_keys_by_node(nil)
  end

  test "list_active_nodes/0", %{node: node} do
    assert [^node] = Storage.list_active_nodes()
  end

  test "list_data_by_node_key/3", %{node: node, metric_table: metric_table} do
    key_name = "test.phoenix"

    Storage.subscribe_for_new_data(node, key_name)

    ObserverWeb.RpcMock
    |> stub(
      :call,
      fn
        ^node, :ets, :lookup, [^metric_table, "metric-keys"], :infinity ->
          # First time: Empty keys
          # Second time: Added key
          called = Process.get("ets_lookup", 0)
          Process.put("ets_lookup", called + 1)

          if called > 0 do
            [{"metric-keys", [key_name]}]
          else
            [{"metric-keys", []}]
          end

        node, module, function, args, timeout ->
          :rpc.call(node, module, function, args, timeout)
      end
    )

    Enum.each(1..5, &Storage.push_data(build_metric(node, key_name, &1)))

    assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                   1_000

    assert [
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Storage.list_data_by_node_key(node |> to_string(), key_name, order: :asc)

    assert [
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _}
           ] = Storage.list_data_by_node_key(node |> to_string(), key_name, order: :desc)

    assert [
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Storage.list_data_by_node_key(node |> to_string(), key_name)
  end

  test "Pruning expiring entries", %{node: node, pid: pid, metric_table: metric_table} do
    key_name = "test.phoenix"

    now = System.os_time(:millisecond)

    Storage.subscribe_for_new_data(node, key_name)

    ObserverWeb.RpcMock
    |> stub(
      :call,
      fn
        ^node, :ets, :lookup, [^metric_table, "metric-keys"], :infinity ->
          # First time: Empty keys
          # Second time: Added key
          called = Process.get("ets_lookup", 0)
          Process.put("ets_lookup", called + 1)

          if called > 0 do
            [{"metric-keys", [key_name]}]
          else
            [{"metric-keys", []}]
          end

        node, module, function, args, timeout ->
          :rpc.call(node, module, function, args, timeout)
      end
    )

    with_mock System, os_time: fn _ -> now - 120_000 end do
      Enum.each(1..5, &Storage.push_data(build_metric(node, key_name, &1)))

      assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                     1_000
    end

    assert [
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _}
           ] = Storage.list_data_by_node_key(node |> to_string(), key_name, order: :asc)

    send(pid, :prune_expired_entries)
    :timer.sleep(100)

    assert [] = Storage.list_data_by_node_key(node |> to_string(), key_name, order: :asc)
  end

  defp build_metric(node, name, value) do
    %{
      metrics: [
        %{
          name: name,
          value: value,
          unit: " millisecond",
          info: "",
          tags: %{status: 200, method: "GET"},
          type: "summary"
        }
      ],
      reporter: node,
      measurements: %{duration: 1_311_711}
    }
  end

  defp create_consumer(context) do
    node = Node.self()
    {:ok, pid} = Storage.start_link(mode: :local, data_retention_period: :timer.minutes(1))

    context
    |> Map.put(:node, node)
    |> Map.put(:pid, pid)
  end

  defp metric_table(context) do
    node = Node.self()
    Map.put(context, :metric_table, String.to_atom("#{node}::observer-web-metrics"))
  end
end
