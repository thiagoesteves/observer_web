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
end
