defmodule ObserverWeb.Telemetry.ObserverStorageTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  alias ObserverWeb.Telemetry.Storage
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :create_consumer
  ]

  test "[un]subscribe_for_new_keys/0", %{node: node} do
    Storage.subscribe_for_new_keys()

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:metrics_new_keys, ^node, ["vm.memory.total"]}, 1_000
  end

  test "[un]subscribe_for_new_data/0", %{node: node} do
    Storage.subscribe_for_new_data(node, "vm.memory.total")

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:metrics_new_data, ^node, "vm.memory.total",
                    %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: _, measurements: _}},
                   1_000

    # Validate by inspection
    Storage.unsubscribe_for_new_data(node, "vm.memory.total")
  end

  test "get_keys_by_node/1 valid node", %{node: node} do
    Storage.subscribe_for_new_data(node, "vm.memory.total")

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

  test "list_data_by_node_key/3 when data is received by observer - handle_cast", %{node: node} do
    key_name = "test.phoenix"

    Storage.subscribe_for_new_data(node, key_name)

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

  test "list_data_by_node_key/3 when data is received by broadcast - handle_info" do
    key_name = "test.phoenix"
    node = :fake@nohost

    Storage.subscribe_for_new_data(node, key_name)

    send(ObserverWeb.Telemetry.Storage, {:nodeup, node})

    Enum.each(
      1..5,
      &Phoenix.PubSub.broadcast(
        ObserverWeb.PubSub,
        "metrics::broadcast",
        {:observer_web_telemetry, build_metric(node, key_name, &1)}
      )
    )

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

  test "list_data_by_node_key/3 ignore when node is not previously up - handle_info" do
    key_name = "test.phoenix"
    node = :fake@nohost

    Storage.subscribe_for_new_data(node, key_name)

    Phoenix.PubSub.broadcast(
      ObserverWeb.PubSub,
      "metrics::broadcast",
      {:observer_web_telemetry, build_metric(node, key_name, 1)}
    )

    assert [] = Storage.list_data_by_node_key(node |> to_string(), key_name, order: :asc)
  end

  test "Add new node, check if data is stored, remove node and check node is available and data contains nil" do
    key_name = "test.phoenix"
    node = :fake@nohost

    Storage.subscribe_for_new_data(node, key_name)

    send(ObserverWeb.Telemetry.Storage, {:nodeup, node})

    Enum.each(1..5, &Storage.push_data(build_metric(node, key_name, &1)))

    assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 5}},
                   1_000

    assert node in Storage.list_active_nodes()

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

    send(ObserverWeb.Telemetry.Storage, {:nodedown, node})

    :timer.sleep(100)

    assert node in Storage.list_active_nodes()

    assert [
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 1, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 2, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 3, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 4, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 5, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: nil, tags: _}
           ] = Storage.list_data_by_node_key(node |> to_string(), key_name)
  end

  test "Testing Node down within a minute that doesn't contain any data" do
    key_name = "test.phoenix"
    node = :fake@nohost

    now = System.os_time(:millisecond)

    Storage.subscribe_for_new_data(node, key_name)

    send(ObserverWeb.Telemetry.Storage, {:nodeup, node})

    with_mock System, os_time: fn _ -> now - 120_000 end do
      Storage.push_data(build_metric(node, key_name, 999))

      assert_receive {:metrics_new_data, ^node, ^key_name, %{timestamp: _, unit: _, value: 999}},
                     1_000
    end

    assert node in Storage.list_active_nodes()

    assert [%ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 999, tags: _}] =
             Storage.list_data_by_node_key(node |> to_string(), key_name, order: :asc)

    send(ObserverWeb.Telemetry.Storage, {:nodedown, node})

    :timer.sleep(100)

    assert node in Storage.list_active_nodes()

    assert [
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: 999, tags: _},
             %ObserverWeb.Telemetry.Data{timestamp: _, unit: _, value: nil, tags: _}
           ] =
             Storage.list_data_by_node_key(node |> to_string(), key_name, order: :asc)
  end

  test "Pruning expiring entries", %{node: node, pid: pid} do
    key_name = "test.phoenix"

    now = System.os_time(:millisecond)

    Storage.subscribe_for_new_data(node, key_name)

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
    {:ok, pid} = Storage.start_link(mode: :observer, data_retention_period: :timer.minutes(1))

    context
    |> Map.put(:node, node)
    |> Map.put(:pid, pid)
  end
end
