defmodule Observer.Web.SettingsComponentLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox
  import Mock

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber
  alias Observer.Web.SettingsComponent

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

    {:noreply, _updated_socket} = SettingsComponent.handle_event("cycle-theme", %{}, socket)

    assert_receive {:update_theme, "dark"}, 1_000

    # Call cycle theme, current dark
    socket = %{socket | assigns: %{socket.assigns | theme: "dark"}}

    {:noreply, _updated_socket} = SettingsComponent.handle_event("cycle-theme", %{}, socket)

    assert_receive {:update_theme, "system"}, 1_000

    # Call cycle theme, current system
    socket = %{socket | assigns: %{socket.assigns | theme: "system"}}

    {:noreply, _updated_socket} = SettingsComponent.handle_event("cycle-theme", %{}, socket)

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
      SettingsComponent.handle_event("update-theme", %{"theme" => "light"}, socket)

    assert_receive {:update_theme, "light"}, 1_000

    {:noreply, _socket} =
      SettingsComponent.handle_event("update-theme", %{"theme" => "dark"}, socket)

    assert_receive {:update_theme, "dark"}, 1_000

    {:noreply, _socket} =
      SettingsComponent.handle_event("update-theme", %{"theme" => "system"}, socket)

    assert_receive {:update_theme, "system"}, 1_000
  end

  test "Check no warning message for matching versions", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    with_mock ObserverWeb.Version,
      status: fn -> %ObserverWeb.Version.Server{} end do
      {:ok, _index_live, html} = live(conn, "/observer/tracing")

      refute html =~ "Version mismatch across nodes:"
    end
  end

  test "Check Warning message for non matching versions", %{conn: conn} do
    RpcStubber.defaults()

    TelemetryStubber.defaults()

    node1 = :node1@nohost
    node2 = :node2@nohost

    with_mock ObserverWeb.Version,
      status: fn ->
        nodes = %{} |> Map.put(node1, "0.1.2") |> Map.put(node2, "0.1.4")
        %ObserverWeb.Version.Server{status: :warning, local: "0.1.0", nodes: nodes}
      end do
      {:ok, _index_live, html} = live(conn, "/observer/tracing")

      assert html =~ "Version mismatch across nodes:"
      assert html =~ "#{node1}"
      assert html =~ "#{node2}"
    end
  end
end
