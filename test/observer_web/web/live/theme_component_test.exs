defmodule Observer.Web.ThemeComponentLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber
  alias Observer.Web.ThemeComponent

  setup :verify_on_exit!

  test "Check the rendered elements are present", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    # Test the rendered output
    assert index_live
           |> element("#theme-menu-toggle")
           |> has_element?()

    assert index_live
           |> element("#theme-menu")
           |> has_element?()
  end

  test "Check cycle theme event", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    # NOTE: Since there are some JS events with some back and forward from the client server
    # the only way to test the events was calling it directly with the liveview socket

    # Get the socket from the LiveView process
    socket = :sys.get_state(index_live.pid).socket

    # Call cycle theme, current light
    socket = %{socket | assigns: %{socket.assigns | theme: "light"}}

    {:noreply, _updated_socket} = ThemeComponent.handle_event("cycle-theme", %{}, socket)

    assert_receive {:update_theme, "dark"}, 1_000

    # Call cycle theme, current dark
    socket = %{socket | assigns: %{socket.assigns | theme: "dark"}}

    {:noreply, _updated_socket} = ThemeComponent.handle_event("cycle-theme", %{}, socket)

    assert_receive {:update_theme, "system"}, 1_000

    # Call cycle theme, current system
    socket = %{socket | assigns: %{socket.assigns | theme: "system"}}

    {:noreply, _updated_socket} = ThemeComponent.handle_event("cycle-theme", %{}, socket)

    assert_receive {:update_theme, "light"}, 1_000
  end

  test "Check update theme event", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    # NOTE: Since there are some JS events with some back and forward from the client server
    # the only way to test the events was calling it directly with the liveview socket

    # Get the socket from the LiveView process
    socket = :sys.get_state(index_live.pid).socket

    {:noreply, _socket} =
      ThemeComponent.handle_event("update-theme", %{"theme" => "light"}, socket)

    assert_receive {:update_theme, "light"}, 1_000

    {:noreply, _socket} =
      ThemeComponent.handle_event("update-theme", %{"theme" => "dark"}, socket)

    assert_receive {:update_theme, "dark"}, 1_000

    {:noreply, _socket} =
      ThemeComponent.handle_event("update-theme", %{"theme" => "system"}, socket)

    assert_receive {:update_theme, "system"}, 1_000
  end
end
