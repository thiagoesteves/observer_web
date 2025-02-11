defmodule Observer.Web.Metrics.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "GET /metrics", %{conn: conn} do
    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> expect(:get_keys_by_node, fn _node -> [] end)

    {:ok, _index_live, html} = live(conn, "/observer/metrics")

    assert html =~ "Live Metrics"
  end

  test "GET /metrics + new key", %{conn: conn} do
    test_pid_process = self()

    metric = "fake.phoenix.metric"

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:get_keys_by_node, 2, fn _node ->
      # First time: initialization call
      # Second time: New key event
      called = Process.get("get_keys_by_node", 0)
      Process.put("get_keys_by_node", called + 1)

      if called > 0 do
        send(test_pid_process, :added_metric)
      end

      [metric]
    end)

    {:ok, liveview, html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    refute html =~ "#{metric}"

    send(liveview_pid, {:metrics_new_keys, nil, nil})

    assert_receive :added_metric, 1_000

    html = render(liveview)

    assert html =~ "#{metric}"
  end

  test "GET /metrics + update form", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    metric = "vm.memory.total"
    metric_id = String.replace(metric, ".", "-")
    test_pid_process = self()

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> stub(:list_data_by_node_key, fn ^node, ^metric, _ ->
      [
        TelemetryFixtures.build_telemetry_data_vm_total_memory(),
        TelemetryFixtures.build_telemetry_data_vm_total_memory(),
        TelemetryFixtures.build_telemetry_data_vm_total_memory()
      ]
    end)
    |> stub(:get_keys_by_node, fn _node -> [metric] end)

    {:ok, liveview, _html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-metrics-#{metric_id}-add-item")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert_receive {:liveview_pid, _liveview_pid}, 1_000

    time = "1 minute"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 1, start_time: time}) =~ time

    time = "5 minutes"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 2, start_time: time}) =~ time

    time = "15 minutes"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 3, start_time: time}) =~ time

    time = "30 minutes"

    liveview
    |> element("#metrics-update-form")
    |> render_change(%{num_cols: 4, start_time: time}) =~ time
  end

  test "Testing NodeDown, removing the current node from the selected services", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    test_pid_process = self()

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> stub(:get_keys_by_node, fn _node -> []    end)

    {:ok, liveview, _html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    html = liveview
    |> element("#metrics-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert html =~ "services:#{node}"

    send(liveview_pid, {:nodedown, Node.self()})

    refute render(liveview) =~ "services:#{node}"
  end

  test "Testing NodeUp, no previous service is removed", %{conn: conn} do
    node = Node.self() |> to_string
    service_id = String.replace(node, "@", "-")
    test_pid_process = self()

    ObserverWeb.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> stub(:get_keys_by_node, fn _node -> []    end)

    {:ok, liveview, _html} = live(conn, "/observer/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    html = liveview
    |> element("#metrics-multi-select-services-#{service_id}-add-item")
    |> render_click()

    assert html =~ "services:#{node}"

    send(liveview_pid, {:nodedown, :fake_node})

    assert render(liveview) =~ "services:#{node}"
  end

end
