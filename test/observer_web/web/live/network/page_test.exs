defmodule Observer.Web.Network.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  defp with_tcp_connection(fun) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, listen_port_number} = :inet.port(listen)
    {:ok, client} = :gen_tcp.connect(~c"localhost", listen_port_number, [:binary, active: false])
    {:ok, accepted} = :gen_tcp.accept(listen, 1_000)

    fun.(listen_port_number)

    :gen_tcp.close(client)
    :gen_tcp.close(accepted)
    :gen_tcp.close(listen)
  end

  test "GET /network renders the ranked inet ports and the sockets section", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    with_tcp_connection(fn listen_port_number ->
      {:ok, index_live, _html} = live(conn, "/observer/network")

      :timer.sleep(50)

      html = render(index_live)
      assert html =~ "Inet Ports"
      assert html =~ "tcp_inet"
      assert html =~ "127.0.0.1:#{listen_port_number}"
      assert html =~ "RECV (Δ)"
      assert html =~ "SENT (Δ)"
      assert html =~ "Sockets (NIF)"
    end)
  end

  test "DETAILS opens and closes the port drill-down panel", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    with_tcp_connection(fn _listen_port_number ->
      {:ok, index_live, _html} = live(conn, "/observer/network")

      :timer.sleep(50)
      render(index_live)

      html =
        index_live
        |> element("#network-select-row-0")
        |> render_click()

      assert html =~ "statistics"
      assert html =~ "options"
      assert html =~ "recv (total)"

      html =
        index_live
        |> element("#network-details-close", "CLOSE")
        |> render_click()

      refute html =~ "recv (total)"
    end)
  end

  test "REFRESH samples immediately and sort can be changed", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    with_tcp_connection(fn _listen_port_number ->
      {:ok, index_live, _html} = live(conn, "/observer/network")

      index_live
      |> element("#network-refresh", "REFRESH")
      |> render_click()

      :timer.sleep(50)

      html =
        index_live
        |> element("#network-update-form")
        |> render_change(%{
          service: to_string(Node.self()),
          sort_by: "recv",
          refresh_seconds: "0"
        })

      assert html =~ "Inet Ports"

      :timer.sleep(50)
      assert render(index_live) =~ "tcp_inet"
    end)
  end

  test "Sampling failures are reported instead of crashing", %{conn: conn} do
    test_pid = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn _node, _module, _function, _args, _timeout ->
      send(test_pid, :sample_requested)
      {:badrpc, :nodedown}
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/network")

    assert_receive :sample_requested, 1_000
    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Could not sample"
    assert html =~ "nodedown"
  end

  test "Stale ticks and NodeUp/NodeDown are handled", %{conn: conn} do
    fake_node = :myapp@nohost
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:network_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/network")

    assert_receive {:network_index_pid, network_index_pid}, 1_000

    send(network_index_pid, {:network_tick, 9_999})
    send(network_index_pid, {:nodeup, fake_node})
    send(network_index_pid, {:nodedown, fake_node})

    :timer.sleep(50)

    assert render(index_live) =~ "Inet Ports"
  end
end
