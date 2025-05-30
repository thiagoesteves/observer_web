defmodule Observer.Web.Apps.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Mock

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "GET /observer/applications", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer/applications")

    assert html =~ "Live Applications"
  end

  test "Adjust Initial Tree Depth", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    html =
      index_live
      |> element("#apps-multi-select-toggle-options")
      |> render_click()

    refute html =~ "4242"

    html =
      index_live
      |> element("#apps-update-form")
      |> render_change(%{initial_tree_depth: "4242"})

    assert html =~ "4242"
  end

  test "Add/Remove Local Service + Kernel App", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-services-#{service}-add-item")
    |> render_click()

    html =
      index_live
      |> element("#apps-multi-select-apps-kernel-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    html =
      index_live
      |> element("#apps-multi-select-apps-kernel-remove-item")
      |> render_click()

    assert html =~ "services:#{node}"
    refute html =~ "apps:kernel"

    html =
      index_live
      |> element("#apps-multi-select-services-#{service}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "apps:kernel"
  end

  test "Add/Remove Kernel App + Local Service", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-apps-kernel-add-item")
    |> render_click()

    html =
      index_live
      |> element("#apps-multi-select-services-#{service}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    html =
      index_live
      |> element("#apps-multi-select-services-#{service}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    html =
      index_live
      |> element("#apps-multi-select-apps-kernel-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "apps:kernel"
  end

  test "Select Service+Apps and select a process to request information", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

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

    pid = Enum.random(:erlang.processes())

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(pid)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert html = render(index_live)

    # Check the Process information is being shown
    assert html =~ "Group Leader"
    assert html =~ "Heap Size"
    refute html =~ "Os Pid"
    refute html =~ "Connected"
  end

  test "Select Service+Apps and select a socket liveview process to request information", %{
    conn: conn
  } do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

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

    pid = Enum.random(:erlang.processes())

    id = "#{inspect(pid)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    with_mock ObserverWeb.Apps.Process,
      info: fn _ ->
        data = %{
          pid: self(),
          registered_name: "name",
          priority: nil,
          trap_exit: nil,
          message_queue_len: 0,
          error_handler: :none,
          relations: %{
            group_leader: :none,
            ancestors: :none,
            links: :none,
            monitored_by: :none,
            monitors: :none
          },
          memory: %{
            total: 0,
            stack_and_heap: 0,
            heap_size: 0,
            stack_size: 0,
            gc_min_heap_size: 0,
            gc_full_sweep_after: 0
          },
          meta: %{
            init: "",
            current: "",
            status: "",
            class: ""
          },
          state: "Phoenix.LiveView.Socket",
          phx_lv_socket: %Phoenix.LiveView.Socket{
            id: "my-test-id",
            assigns: %{flag: true},
            host_uri: %URI{scheme: "https", port: 55_555}
          }
        }

        send(test_pid_process, :requested_mock_info)
        data
      end do
      send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
      send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

      assert_receive :requested_mock_info, 1_000
    end

    assert html = render(index_live)

    # Check the Process information is being shown
    assert html =~ "Group Leader"
    assert html =~ "Heap Size"
    assert html =~ "Phoenix.LiveView.Socket"
    assert html =~ "my-test-id"
    assert html =~ "Phoenix.LiveView.Socket - URI"
    assert html =~ "55555"
    assert html =~ "Phoenix.LiveView.Socket - Assigns"
    assert html =~ "flag =&gt; true"
  end

  test "Select Service+Apps and select a process that is dead or doesn't exist", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

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

    series_name = "#{Node.self()}::kernel"

    id = "#PID<0.0.11111>"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert html = render(index_live)

    # Check the Process information is not being shown
    assert html =~ "Process #PID&lt;0.0.11111&gt; is either dead or protected"
  end

  test "Select Service+Apps and select a port to request information", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

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

    port = Enum.random(:erlang.ports())

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(port)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert html = render(index_live)

    # Check the Process information is being shown
    refute html =~ "Group Leader"
    refute html =~ "Heap Size"
    assert html =~ "Os Pid"
    assert html =~ "Connected"
  end

  test "Select Service+Apps and select a port that is dead or doesn't exist", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

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

    series_name = "#{Node.self()}::kernel"

    id = "#Port<0.100>"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert html = render(index_live)

    # Check the Port information is not being shown
    assert html =~ "Port #Port&lt;0.100&gt; is either dead or protected"
  end

  test "Select Service+Apps and select a reference to request information", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

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

    reference = make_ref()

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(reference)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert html = render(index_live)

    # Check the Process information is being shown
    refute html =~ "Group Leader"
    refute html =~ "Heap Size"
    refute html =~ "Os Pid"
    refute html =~ "Connected"
  end

  @tag :capture_log
  test "Update buttom with Observer Web App + Local Service", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-apps-observer_web-add-item")
    |> render_click()

    html =
      index_live
      |> element("#apps-multi-select-services-#{service}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:observer_web"

    assert index_live
           |> element("#apps-multi-select-update", "UPDATE")
           |> render_click() =~ "apps:observer_web"
  end

  test "Testing NodeUp/NodeDown", %{conn: conn} do
    fake_node = :myapp@nohost
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information ->
      send(test_pid_process, {:apps_page_pid, self()})
      :rpc.pinfo(pid, information)
    end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-apps-kernel-add-item")
    |> render_click()

    html =
      index_live
      |> element("#apps-multi-select-services-#{service}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    # Check node up/down doesn't change the selected items
    send(apps_page_pid, {:nodeup, fake_node})
    send(apps_page_pid, {:nodedown, fake_node})

    assert html = render(index_live)
    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"
  end
end
