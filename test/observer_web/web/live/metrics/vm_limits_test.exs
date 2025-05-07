defmodule Observer.Web.Metrics.VmLimitsTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  %{
    1 => %{metric: "vm.atom.total"},
    2 => %{metric: "vm.port.total"},
    3 => %{metric: "vm.process.total"}
  }
  |> Enum.each(fn {element, %{metric: metric}} ->
    test "#{element} - Add/Remove Service + #{metric}", %{conn: conn} do
      node = Node.self() |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      TelemetryStubber.defaults()
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
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
  end)

  %{
    1 => %{metric: "vm.atom.total"},
    2 => %{metric: "vm.port.total"},
    3 => %{metric: "vm.process.total"}
  }
  |> Enum.each(fn {element, %{metric: metric}} ->
    test "#{element} - #{metric} + Service", %{conn: conn} do
      node = Node.self() |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      TelemetryStubber.defaults()
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:unsubscribe_for_new_data, fn ^node, ^metric -> :ok end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [] end)
      |> stub(:get_keys_by_node, fn _node -> [metric] end)

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
  end)

  %{
    1 => %{
      metric: "vm.atom.total",
      init: 2_000_000,
      update: 3_000_000
    },
    2 => %{
      metric: "vm.port.total",
      init: 4_000_000,
      update: 5_000_000
    },
    3 => %{
      metric: "vm.process.total",
      init: 6_000_000,
      update: 7_000_000
    }
  }
  |> Enum.each(fn {element, %{metric: metric, init: init, update: update}} ->
    test "#{element} - Beam VM statistics Start - Init and Push #{metric}", %{
      conn: conn
    } do
      node = Node.self() |> to_string
      service_id = String.replace(node, "@", "-")
      metric = unquote(metric)
      metric_id = String.replace(metric, ".", "-")

      init = unquote(init)
      update = unquote(update)

      test_pid_process = self()

      TelemetryStubber.defaults()
      |> expect(:subscribe_for_new_keys, fn -> :ok end)
      |> expect(:subscribe_for_new_data, fn ^node, ^metric ->
        send(test_pid_process, {:liveview_pid, self()})
        :ok
      end)
      |> expect(:list_data_by_node_key, fn ^node, ^metric, _ ->
        [
          TelemetryFixtures.build_telemetry_beam_vm_total(1_737_982_400_500, init)
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
      assert html =~ "2025-01-27 12:53:20.500"

      send(
        liveview_pid,
        {:metrics_new_data, node, metric,
         TelemetryFixtures.build_telemetry_beam_vm_total(1_737_982_400_700, update)}
      )

      # assert live updated data
      html = render(liveview)
      assert html =~ "2025-01-27 12:53:20.700Z"

      # Assert nil data received, this will indicate the application has restarted
      send(
        liveview_pid,
        {:metrics_new_data, node, metric,
         TelemetryFixtures.build_telemetry_beam_vm_total(1_737_982_379_789, nil)}
      )

      html = render(liveview)
      assert html =~ "2025-01-27 12:52:59.789Z"
    end
  end)
end
