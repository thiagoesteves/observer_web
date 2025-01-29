defmodule Observer.Web.IndexLiveTest do
  use Observer.Web.ConnCase, async: false

  test "forbidding mount using a resolver callback", %{conn: conn} do
    assert {:error, {:redirect, redirect}} = live(conn, "/observer-limited")
    assert %{to: "/", flash: %{"error" => "Access forbidden"}} = redirect
  end
end
