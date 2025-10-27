defmodule Observer.Web.Apps.VmPortMemoryTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Observer.Web.Helpers
  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.Monitor
  alias ObserverWeb.TelemetryFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "Select Service+Apps and Toggle port Monitor", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()
    {:ok, id} = :gen_tcp.listen(0, [])
    {:ok, %{metric: metric}} = Monitor.start_id_monitor(id)

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_data, fn _node, ^metric ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> expect(:list_data_by_node_key, fn _node, ^metric, _options ->
      [
        TelemetryFixtures.build_telemetry_data_vm_port_total_memory(1_737_982_379_123)
      ]
    end)

    # Stop monitoring so when process is selected, the initial value is OFF
    Monitor.stop_id_monitor(id)

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-apps-kernel-add-item")
    |> render_click()

    index_live
    |> element("#apps-multi-select-services-#{service}-add-item")
    |> render_click()

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(id)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    html =
      index_live
      |> element("input[type=\"checkbox\"]")
      |> render_click()

    assert html =~ "Memory monitor enabled for id: #Port"

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    # assert initial data
    assert html =~ "2025-01-27 12:52:59.123Z"

    # assert live updated data
    send(
      liveview_pid,
      {:metrics_new_data, node, metric,
       TelemetryFixtures.build_telemetry_data_vm_port_total_memory(1_737_982_379_456)}
    )

    html = render(index_live)
    assert html =~ "2025-01-27 12:52:59.456Z"

    assert index_live
           |> element("input[type=\"checkbox\"]")
           |> render_click() =~ "Memory monitor disabled for id: #Port"

    html = render(index_live)
    refute html =~ "2025-01-27 12:52:59.456Z"
  end

  test "Select Service+Apps and a Monitored port and toggle monitor off", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()
    {:ok, id} = :gen_tcp.listen(0, [])
    {:ok, %{metric: metric}} = Monitor.start_id_monitor(id)
    telemetry_data = TelemetryFixtures.build_telemetry_data_vm_port_total_memory()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()
    |> expect(:subscribe_for_new_data, fn ^node, ^metric -> :ok end)
    |> expect(:list_data_by_node_key, fn ^node, ^metric, _ -> [telemetry_data] end)

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-apps-kernel-add-item")
    |> render_click()

    index_live
    |> element("#apps-multi-select-services-#{service}-add-item")
    |> render_click()

    # pid = Enum.random(:erlang.processes())

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(id)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert index_live
           |> element("input[type=\"checkbox\"]")
           |> render_click() =~ "Memory monitor disabled for id: #Port"
  end
end
