defmodule Observer.Web.Metrics.VmSchedulerUtilizationTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  @metric "vm.scheduler.utilization"

  test "Add/Remove Service + #{@metric}", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = Helpers.normalize_id(node)
    metric = @metric
    metric_id = Helpers.normalize_id(metric)

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
    |> stub(:get_keys_by_node, fn _ -> [metric] end)

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
      |> element("#metrics-multi-select-metrics-#{metric_id}-remove-item")
      |> render_click()

    refute html =~ "metrics:#{metric}"
  end

  test "Utilization chart - Init and Push #{@metric}", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = Helpers.normalize_id(node)
    metric = @metric
    metric_id = Helpers.normalize_id(metric)

    test_pid_process = self()

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ ->
      [
        TelemetryFixtures.build_telemetry_data(1_737_982_400_666.0, 12.34)
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

    # assert initial data rendered by the utilization chart (percent scale + area series)
    assert html =~ "2025-01-27 12:53:20.666"
    assert html =~ "12.34"
    assert html =~ "{value} %"
    assert html =~ "Utilization"

    # assert live updated data
    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data(1_737_982_379_777, 98.76)}
    )

    html = render(liveview)
    assert html =~ "2025-01-27 12:52:59.777Z"
    assert html =~ "98.76"

    # A nil value (application restarted) must not crash the chart
    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data(1_737_982_379_999, nil)}
    )

    html = render(liveview)
    assert html =~ "2025-01-27 12:52:59.999Z"
  end
end
