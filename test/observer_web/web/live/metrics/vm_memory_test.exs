defmodule Observer.Web.Metrics.VmMemoryTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "Add/Remove Service + vm.memory.total", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")
    telemetry_data = TelemetryFixtures.build_telemetry_data_vm_total_memory()

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)
    |> stub(:get_keys_by_node, fn _node -> [metric] end)

    {:ok, liveview, _html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-services-#{service_id}-add-item")
    |> render_click()

    html =
      liveview
      |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-metrics-#{metric_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "metrics:#{metric}"
  end

  test "Add/Remove vm.memory.total + Service", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")
    telemetry_data = TelemetryFixtures.build_telemetry_data_vm_total_memory()

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)
    |> stub(:get_keys_by_node, fn _ -> [metric] end)

    {:ok, liveview, _html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
    |> render_click()

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-metrics-#{metric_id}-remove-item")
      |> render_click()

    assert html =~ "services:#{node}"
    refute html =~ "metrics:#{metric}"

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "metrics:#{metric}"
  end

  test "Init and Push vm.memory.total data", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")

    test_pid_process = self()

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ ->
      [
        TelemetryFixtures.build_telemetry_data_vm_total_memory(1_737_982_379_123)
      ]
    end)
    |> stub(:get_keys_by_node, fn _ -> [metric] end)

    {:ok, liveview, _html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
    |> render_click()

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-add-item")
      |> render_click()

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    # assert initial data
    assert html =~ "2025-01-27 12:52:59.123Z"

    # assert live updated data
    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data_vm_total_memory(1_737_982_379_456)}
    )

    html = render(liveview)
    assert html =~ "2025-01-27 12:52:59.456Z"

    # Assert nil data received, this will indicate the application has restarted
    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data(1_737_982_379_789, nil)}
    )

    html = render(liveview)
    assert html =~ "2025-01-27 12:52:59.789Z"
  end
end
