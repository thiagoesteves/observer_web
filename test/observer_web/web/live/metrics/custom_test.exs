defmodule Observer.Web.Metrics.CustomTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Observer.Web.Components.Metrics.Custom
  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  describe "renders?/1" do
    test "claims metrics no dedicated component supports" do
      assert Custom.renders?("my_app.repo.query.total_time")
      assert Custom.renders?("my_app.orders.created.count")
    end

    test "leaves built-in metrics to their dedicated components" do
      refute Custom.renders?("vm.memory.total")
      refute Custom.renders?("vm.total_run_queue_lengths.cpu")
      refute Custom.renders?("vm.atom.total")
      refute Custom.renders?("vm.scheduler.utilization")
      refute Custom.renders?("phoenix.router_dispatch.stop.duration")
      refute Custom.renders?("phoenix.liveview.socket.default.total")
      refute Custom.renders?("vm.process.memory.worker.total")
      refute Custom.renders?("vm.port.memory.socket.total")
    end
  end

  test "Add/Remove Service + custom host metric", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = Helpers.normalize_id(node)
    metric = "my_app.repo.query.total_time"
    metric_id = Helpers.normalize_id(metric)

    data = [
      TelemetryFixtures.build_telemetry_data(1_700_000_000_000, 12.5, "millisecond"),
      TelemetryFixtures.build_telemetry_data(1_700_000_060_000, nil, ""),
      TelemetryFixtures.build_telemetry_data(1_700_000_120_000, 15.1, "millisecond")
    ]

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> data end)
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
    assert html =~ "#{metric} ["
    assert html =~ "millisecond"

    html =
      liveview
      |> element("#metrics-multi-select-services-#{service_id}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "metrics:#{metric}"
  end
end
