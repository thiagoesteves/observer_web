defmodule Observer.Web.IndexLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  setup :verify_on_exit!

  test "forbidding mount using a resolver callback", %{conn: conn} do
    ObserverWeb.TelemetryMock
    |> stub(:push_data, fn _event -> :ok end)

    assert {:error, {:redirect, redirect}} = live(conn, "/observer-limited")
    assert %{to: "/", flash: %{"error" => "Access forbidden"}} = redirect
  end

  test "Check iframe OFF allows root buttom", %{conn: conn} do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    ObserverWeb.TelemetryMock
    |> stub(:push_data, fn _event -> :ok end)

    {:ok, _index_live, html} = live(conn, "/observer/tracing")

    assert html =~ "Live Tracing"
    assert html =~ "ROOT"
  end

  test "Check iframe ON doesn't allow root buttom", %{conn: conn} do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    ObserverWeb.TelemetryMock
    |> stub(:push_data, fn _event -> :ok end)

    {:ok, _index_live, html} = live(conn, "/observer/tracing?iframe=true")

    assert html =~ "Live Tracing"
    refute html =~ "ROOT"
  end
end
