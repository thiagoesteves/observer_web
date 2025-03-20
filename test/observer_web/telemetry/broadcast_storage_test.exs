defmodule ObserverWeb.BroadcastStorageTest do
  use ExUnit.Case, async: false

  alias ObserverWeb.Telemetry.Storage
  alias ObserverWeb.TelemetryFixtures

  setup [:create_consumer]

  test "push_data/1", %{node: node} do
    Phoenix.PubSub.subscribe(ObserverWeb.PubSub, "metrics::broadcast")

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:observer_web_telemetry, %{reporter: ^node, metrics: _}}, 1_000
  end

  test "list_active_nodes/0" do
    assert [] == Storage.list_active_nodes()
  end

  test "Check broadcast doesn't store any data", %{node: node} do
    key_name = "vm.memory.total"

    Phoenix.PubSub.subscribe(ObserverWeb.PubSub, "metrics::broadcast")

    node
    |> TelemetryFixtures.build_reporter_vm_memory_total()
    |> Storage.push_data()

    assert_receive {:observer_web_telemetry, _}, 1_000

    assert [] == Storage.list_data_by_node_key(node |> to_string(), key_name)
    assert [] == Storage.get_keys_by_node(node)
    assert [] == Storage.list_active_nodes()
  end

  defp create_consumer(context) do
    node = Node.self()
    {:ok, pid} = Storage.start_link(mode: :broadcast)

    context
    |> Map.put(:node, node)
    |> Map.put(:pid, pid)
  end
end
