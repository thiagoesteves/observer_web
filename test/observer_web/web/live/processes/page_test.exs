defmodule Observer.Web.Processes.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "GET /processes renders the summary and the ranked table", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Processes:"
    assert html =~ "Run Queue:"
    assert html =~ "NAME"
    assert html =~ "MEMORY"
    assert html =~ "REDUCTIONS"
    assert html =~ "MSG QUEUE"
    assert html =~ "CURRENT FUNCTION"
  end

  test "Changing sort and limit re-ranks the table", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    :timer.sleep(50)

    html =
      index_live
      |> element("#processes-update-form")
      |> render_change(%{
        service: to_string(Node.self()),
        sort_by: "memory",
        limit: "25",
        refresh_seconds: "0"
      })

    assert html =~ "MEMORY"

    :timer.sleep(50)

    html = render(index_live)
    refute html =~ "REDUCTIONS (Δ)"
    assert html =~ "Processes:"
  end

  test "REFRESH button samples immediately", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    index_live
    |> element("#processes-refresh", "REFRESH")
    |> render_click()

    :timer.sleep(50)

    assert render(index_live) =~ "Processes:"
  end

  test "Row DETAILS opens and closes the drill-down panel", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    :timer.sleep(50)
    render(index_live)

    html =
      index_live
      |> element("#processes-select-row-0")
      |> render_click()

    assert html =~ "Process #PID&lt;"
    assert html =~ "current stacktrace"

    html =
      index_live
      |> element("#processes-details-close", "CLOSE")
      |> render_click()

    refute html =~ "current stacktrace"
  end

  test "Sampling failures are reported instead of crashing", %{conn: conn} do
    test_pid = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      case function do
        :etop_collect ->
          send(test_pid, :sample_requested)
          {:badrpc, :nodedown}

        _other ->
          :rpc.call(node, module, function, args, timeout)
      end
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    assert_receive :sample_requested, 1_000
    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Could not sample"
    assert html =~ "nodedown"
  end

  test "Stale ticks from a cancelled refresh chain are ignored", %{conn: conn} do
    fake_node = :myapp@nohost
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:processes_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    assert_receive {:processes_index_pid, processes_index_pid}, 1_000

    send(processes_index_pid, {:processes_tick, 9_999})
    send(processes_index_pid, {:nodeup, fake_node})
    send(processes_index_pid, {:nodedown, fake_node})

    :timer.sleep(50)

    assert render(index_live) =~ "Processes:"
  end

  test "Control changes, unknown rows and nodedown of the selected service are safe", %{
    conn: conn
  } do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/processes")

    :timer.sleep(50)
    render(index_live)

    # Open the details panel, then refresh: the panel follows the newest sample
    index_live
    |> element("#processes-select-row-0")
    |> render_click()

    index_live
    |> element("#processes-refresh", "REFRESH")
    |> render_click()

    :timer.sleep(50)
    assert render(index_live) =~ "current stacktrace"

    # Unknown service (falls back to the local node and clears state), message-queue sort and
    # an invalid limit (falls back to the default)
    index_live
    |> element("#processes-update-form")
    |> render_change(%{
      service: "ghost@nohost",
      sort_by: "message_queue_len",
      limit: "abc",
      refresh_seconds: "0"
    })

    :timer.sleep(50)
    assert render(index_live) =~ "Processes:"

    # A stale/out-of-range row index is ignored
    render_click(index_live, "processes-select-row", %{"index" => "9999"})

    # Losing the selected service falls back to the local node
    send(index_live.pid, {:nodedown, Node.self()})
    :timer.sleep(50)
    assert render(index_live) =~ "Processes:"
  end
end
