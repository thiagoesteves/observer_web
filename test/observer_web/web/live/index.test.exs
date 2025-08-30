defmodule Observer.Web.IndexLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

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
end
