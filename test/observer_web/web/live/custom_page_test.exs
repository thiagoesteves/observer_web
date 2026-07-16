defmodule Observer.Web.CustomPageTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    :ok
  end

  test "GET /fruits renders the registered custom page", %{conn: conn} do
    {:ok, _live, html} = live(conn, "/observer/fruits")

    assert html =~ "Bananas and apples"
    assert html =~ ":all"
  end

  test "custom pages appear in the navigation", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/observer/system")

    :timer.sleep(50)

    html = render(live)
    assert html =~ "nav-fruits"
    assert html =~ "FRUITS"
  end

  test "unknown pages still fall back to the default page", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/observer/not-a-page")

    :timer.sleep(50)

    assert render(live) =~ "Memory Allocators"
  end

  test "default callback implementations keep the parent flow working", %{conn: conn} do
    {:ok, live, _html} = live(conn, "/observer/fruits")

    # handle_parent_event/3 default: any unhandled phx event is a no-op
    assert render_hook(live, "some-unknown-event", %{}) =~ "Bananas and apples"
  end
end
