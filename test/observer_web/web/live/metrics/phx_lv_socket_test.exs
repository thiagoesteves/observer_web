defmodule Observer.Web.Metrics.PhxLvSocketTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "Add/Remove Service + phoenix.liveview.socket.total", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "phoenix.liveview.socket.total"
    metric_id = String.replace(metric, ".", "-")
    telemetry_data = TelemetryFixtures.build_telemetry_data_phx_lv_socket_total()

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)
    |> stub(:get_keys_by_node, fn _node -> [metric] end)
    |> stub(:push_data, fn _event -> :ok end)

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

  test "Add/Remove phoenix.liveview.socket.totall + Service", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "phoenix.liveview.socket.total"
    metric_id = String.replace(metric, ".", "-")
    telemetry_data = TelemetryFixtures.build_telemetry_data_phx_lv_socket_total()

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)
    |> stub(:get_keys_by_node, fn _ -> [metric] end)
    |> stub(:push_data, fn _event -> :ok end)

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

  test "Init and Push phoenix.liveview.socket.totall data", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "phoenix.liveview.socket.total"
    metric_id = String.replace(metric, ".", "-")

    test_pid_process = self()

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ ->
      [
        TelemetryFixtures.build_telemetry_data_phx_lv_socket_total(1_737_982_379_123)
      ]
    end)
    |> stub(:get_keys_by_node, fn _ -> [metric] end)
    |> stub(:push_data, fn _event -> :ok end)

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

    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data_phx_lv_socket_total(1_737_982_379_456)}
    )

    # assert live updated data
    html = render(liveview)
    assert html =~ "2025-01-27 12:52:59.456Z"
  end
end
