defmodule Observer.Web.System.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "GET /system renders the runtime snapshot, limits and allocators", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/system")

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "OTP: #{:erlang.system_info(:otp_release)}"
    assert html =~ "Schedulers:"
    assert html =~ "Uptime:"
    assert html =~ "Limits"
    assert html =~ "Processes"
    assert html =~ "ETS Tables"
    assert html =~ "Memory Allocators"
    assert html =~ "binary_alloc"
    assert html =~ "UTILIZATION"
  end

  test "REFRESH re-collects the snapshot", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/system")

    index_live
    |> element("#system-refresh", "REFRESH")
    |> render_click()

    :timer.sleep(50)

    assert render(index_live) =~ "Memory Allocators"
  end

  test "Snapshot failures are reported instead of crashing", %{conn: conn} do
    test_pid = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn _node, _module, _function, _args, _timeout ->
      send(test_pid, :snapshot_requested)
      {:badrpc, :nodedown}
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/system")

    assert_receive :snapshot_requested, 1_000
    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Could not read"
    assert html =~ "nodedown"
  end

  test "NodeUp/NodeDown refresh the service list", %{conn: conn} do
    fake_node = :myapp@nohost
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:system_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/system")

    assert_receive {:system_index_pid, system_index_pid}, 1_000

    send(system_index_pid, {:nodeup, fake_node})
    send(system_index_pid, {:nodedown, fake_node})

    :timer.sleep(50)

    assert render(index_live) =~ "Memory Allocators"
  end
end
