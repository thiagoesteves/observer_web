defmodule Observer.Web.Apps.AggregationTest do
  use Observer.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Observer.Web.Helpers
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "Applications Summary lists counts and LOAD STATS fills versions and totals", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/applications")

    index_live
    |> element("#apps-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#apps-multi-select-apps-kernel-add-item")
    |> render_click()

    html =
      index_live
      |> element("#apps-multi-select-services-#{service}-add-item")
      |> render_click()

    # Counts are available immediately (pure tree walk), stats not yet loaded
    assert html =~ "Applications Summary"
    assert html =~ "kernel"
    assert html =~ "PROCESSES"
    assert html =~ "LOAD STATS"

    html =
      index_live
      |> element("#apps-load-stats", "LOAD STATS")
      |> render_click()

    # Version and stat sums are filled in after loading
    kernel_version = Application.spec(:kernel, :vsn) |> to_string()
    assert html =~ kernel_version
    assert html =~ ~r/ (KB|MB|GB)/

    # Deselecting the app removes its row (and the section, since nothing is selected)
    html =
      index_live
      |> element("#apps-multi-select-apps-kernel-remove-item")
      |> render_click()

    refute html =~ "Applications Summary"
  end
end
