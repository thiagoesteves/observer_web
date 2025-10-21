defmodule Observer.Web.IndexLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.IndexLive, as: ObserverLive
  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup :verify_on_exit!

  test "forbidding mount using a resolver callback", %{conn: conn} do
    TelemetryStubber.defaults()

    assert {:error, {:redirect, redirect}} = live(conn, "/observer-limited")
    assert %{to: "/", flash: %{"error" => "Access forbidden"}} = redirect
  end

  test "Check iframe OFF allows root button", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer/tracing")

    assert html =~ "Live Tracing"
    assert html =~ "ROOT"
  end

  test "Check iframe ON doesn't allow root button", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer/tracing?iframe=true")

    assert html =~ "Live Tracing"
    refute html =~ "ROOT"
  end

  test "Check Update Theme", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    # NOTE: This test could use send() but it would have to add a delay, so it was
    #       called directly

    # Get the socket from the LiveView process
    socket = :sys.get_state(index_live.pid).socket

    {:noreply, updated_socket} =
      ObserverLive.handle_info({:update_theme, "dark"}, socket)

    assert updated_socket.assigns.theme == "dark"

    {:noreply, updated_socket} =
      ObserverLive.handle_info({:update_theme, "light"}, socket)

    assert updated_socket.assigns.theme == "light"

    {:noreply, updated_socket} =
      ObserverLive.handle_info({:update_theme, "system"}, socket)

    assert updated_socket.assigns.theme == "system"
  end

  test "Check Clear Flash", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    # Get the socket from the LiveView process
    socket = :sys.get_state(index_live.pid).socket

    {:noreply, _updated_socket} =
      ObserverLive.handle_event("clear-flash", %{}, socket)
  end
end
