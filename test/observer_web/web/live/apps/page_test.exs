defmodule Observer.Web.Apps.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Mock

  alias Observer.Web.Helpers
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

  test "Adjust Get State Timeout", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    html =
      index_live
      |> element("#apps-multi-select-toggle-options")
      |> render_click()

    refute html =~ "9900"

    html =
      index_live
      |> element("#apps-update-form")
      |> render_change(%{get_state_timeout: "9900"})

    assert html =~ "9900"
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
      info: fn _pid, _timeout ->
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
          dictionary: [],
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

  test "Select Service+Apps and Kill a process", %{conn: conn} do
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

    {:ok, pid} =
      Task.start(fn ->
        # Perform a long-running operation
        :timer.sleep(30_000)
        "Long-running task complete!"
      end)

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(pid)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert index_live
           |> element("#process-kill-button")
           |> render_click() =~ "Are you sure you want to terminate process pid:"

    assert index_live
           |> element("#confirm-button-#{Helpers.identifier_to_safe_id(id)}")
           |> render_click() =~ "successfully terminated"

    refute Process.alive?(pid)
  end

  test "Select Service+Apps and Cancel before killing a process", %{conn: conn} do
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

    assert index_live
           |> element("#process-kill-button")
           |> render_click() =~ "Are you sure you want to terminate process pid:"

    index_live
    |> element("#cancel-button-#{Helpers.identifier_to_safe_id(id)}")
    |> render_click()

    assert Process.alive?(pid)
  end

  test "Select Service+Apps and Garbage Collect a process", %{conn: conn} do
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

    assert index_live
           |> element("#process-clean-memory-button")
           |> render_click() =~ "successfully garbage collected"
  end

  test "Select Service+Apps and Toggle process Monitor", %{conn: conn} do
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

    assert index_live
           |> element("input[type=\"checkbox\"]")
           |> render_click() =~ "Memory monitor enabled for process pid:"

    assert index_live
           |> element("input[type=\"checkbox\"]")
           |> render_click() =~ "Memory monitor disabled for process pid:"
  end

  test "Select Service+Apps and Send a message to a process", %{conn: conn} do
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

    {:ok, pid} =
      Task.start_link(fn ->
        # Perform a long-running operation
        :timer.sleep(30_000)
        "Long-running task complete!"
      end)

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(pid)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    index_live
    |> element("#process-send-msg-form")
    |> render_change(%{"process-send-message" => "{:hello, :world}"})

    assert index_live
           |> element("#process-send-msg-form")
           |> render_submit() =~ "Message sent to process pid:"
  end

  test "Select Service+Apps and cannot send an invalid message to a process", %{conn: conn} do
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

    assert index_live
           |> element("#process-send-msg-form")
           |> render_change(%{"process-send-message" => "invalid"}) =~
             "border-red-200 focus:border-red-400 hover:border-red-300"
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

  test "Select Service+Apps and close a port", %{conn: conn} do
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

    port = Port.open({:spawn, "sleep 30000"}, [:binary])

    # Send the request 2 times to validate the path where the request
    # was already executed.
    id = "#{inspect(port)}"
    series_name = "#{Node.self()}::kernel"

    assert_receive {:apps_page_pid, apps_page_pid}, 1_000

    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})
    send(apps_page_pid, {"request-process", %{"id" => id, "series_name" => series_name}})

    assert index_live
           |> element("#port-close-button")
           |> render_click() =~ "Are you sure you want to close port id:"

    index_live
    |> element("#confirm-button-#{Helpers.identifier_to_safe_id(id)}")
    |> render_click()

    refute Port.info(port)
  end

  test "Select Service+Apps and Cancel before closing a port", %{conn: conn} do
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

    assert index_live
           |> element("#port-close-button")
           |> render_click() =~ "Are you sure you want to close port id:"

    index_live
    |> element("#cancel-button-#{Helpers.identifier_to_safe_id(id)}")
    |> render_click()

    assert Port.info(port)
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
  test "Update button with Observer Web App + Local Service", %{conn: conn} do
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
