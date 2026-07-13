defmodule Observer.Web.Crashdump.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.CrashdumpFixtures

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup do
    original_dirs = Application.get_env(:observer_web, :crashdump_dirs)

    :ok = Supervisor.terminate_child(ObserverWeb.Application, ObserverWeb.Crashdump.Server)
    {:ok, _pid} = Supervisor.restart_child(ObserverWeb.Application, ObserverWeb.Crashdump.Server)

    on_exit(fn ->
      restore(:crashdump_dirs, original_dirs)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:observer_web, key)
  defp restore(key, value), do: Application.put_env(:observer_web, key, value)

  defp await_loaded(index_live, retries \\ 100)

  defp await_loaded(_index_live, 0), do: raise("dump never finished loading")

  defp await_loaded(index_live, retries) do
    if render(index_live) =~ "Slogan:" do
      :ok
    else
      Process.sleep(100)
      await_loaded(index_live, retries - 1)
    end
  end

  test "Offers upload and lists dumps on the host", %{conn: conn} do
    %{dir: dir} = CrashdumpFixtures.ensure_dump!()
    Application.put_env(:observer_web, :crashdump_dirs, [dir])

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer/crashdump")

    assert html =~ "Upload a crash dump"
    assert html =~ "Crash Dumps on this host"
    assert html =~ "erl_crash.dump"
    assert html =~ "MODIFIED"
  end

  test "Shows the upload zone and handles validate/submit without a pending entry", %{conn: conn} do
    Application.delete_env(:observer_web, :crashdump_dirs)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, html} = live(conn, "/observer/crashdump")

    assert html =~ "Upload a crash dump"
    # No host directory configured, so no host-dump table
    refute html =~ "Crash Dumps on this host"

    # The validate handler exists (LiveView needs it for upload entry tracking)
    index_live
    |> element("#crashdump-upload-form")
    |> render_change(%{"_target" => ["dump"]})

    # Submitting with no pending entry is a no-op (the empty-consume branch)
    index_live
    |> element("#crashdump-upload-form")
    |> render_submit()

    refute render(index_live) =~ "Slogan:"
  end

  test "Lists, loads from the host directory and browses a real crash dump", %{conn: conn} do
    %{dir: dir} = CrashdumpFixtures.ensure_dump!()
    Application.put_env(:observer_web, :crashdump_dirs, [dir])

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/crashdump")

    index_live
    |> element("#crashdump-load-0", "LOAD")
    |> render_click()

    await_loaded(index_live)

    html = render(index_live)
    assert html =~ "observer web test crash"
    assert html =~ "Processes at crash time"
    assert html =~ "CURRENT FUNCTION"
    assert html =~ "REDUCTIONS"

    # Search and sort re-rank the table
    html =
      index_live
      |> element("#crashdump-update-form")
      |> render_change(%{sort_by: "reds", search: "init"})

    assert html =~ "Processes at crash time"

    index_live
    |> element("#crashdump-update-form")
    |> render_change(%{sort_by: "memory", search: ""})

    # Drill into the first process and close the panel again
    html =
      index_live
      |> element("#crashdump-select-row-0")
      |> render_click()

    assert html =~ "stack dump"

    html =
      index_live
      |> element("#crashdump-details-close", "CLOSE")
      |> render_click()

    refute html =~ "stack dump"

    # Out-of-range and non-numeric indexes are ignored
    render_click(index_live, "crashdump-select-row", %{"index" => "99999"})
    render_click(index_live, "crashdump-load", %{"index" => "99999"})
    render_click(index_live, "crashdump-select-row", %{"index" => "abc"})

    # REFRESH re-lists the dump files
    index_live
    |> element("#crashdump-refresh", "REFRESH")
    |> render_click()

    assert render(index_live) =~ "erl_crash.dump"
  end
end
