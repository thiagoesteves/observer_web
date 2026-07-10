defmodule Observer.Web.Ets.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup do
    original = Application.get_env(:observer_web, :table_content_inspection)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:observer_web, :table_content_inspection)
      else
        Application.put_env(:observer_web, :table_content_inspection, original)
      end
    end)

    :ok
  end

  test "GET /ets renders the summary and the tables list", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Tables:"
    assert html =~ "Total memory:"
    assert html =~ "NAME"
    assert html =~ "PROTECTION"
    assert html =~ "OWNER"
    assert html =~ "MEMORY"
    assert html =~ "ac_tab"
  end

  test "Search filters the list and sort by name orders it", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    :timer.sleep(50)

    html =
      index_live
      |> element("#ets-update-form")
      |> render_change(%{
        service: to_string(Node.self()),
        sort_by: "name",
        search: "ac_tab"
      })

    assert html =~ "ac_tab"
    assert html =~ "Showing:"
    refute html =~ "code_names"
  end

  test "DETAILS shows metadata and the disabled-content notice by default", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    :timer.sleep(50)
    render(index_live)

    html =
      index_live
      |> element("#ets-select-row-0")
      |> render_click()

    assert html =~ "protection:"
    assert html =~ "Content inspection is disabled"

    html =
      index_live
      |> element("#ets-details-close", "CLOSE")
      |> render_click()

    refute html =~ "Content inspection is disabled"
  end

  test "DETAILS previews contents when inspection is enabled", %{conn: conn} do
    Application.put_env(:observer_web, :table_content_inspection, true)

    table = :ets.new(:ets_page_preview_test, [:named_table, :public])
    :ets.insert(table, {:preview_key, "preview_value"})

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    :timer.sleep(50)
    render(index_live)

    index_live
    |> element("#ets-update-form")
    |> render_change(%{
      service: to_string(Node.self()),
      sort_by: "memory",
      search: "ets_page_preview_test"
    })

    html =
      index_live
      |> element("#ets-select-row-0")
      |> render_click()

    assert html =~ "First objects (bounded preview)"
    assert html =~ "preview_key"
    assert html =~ "preview_value"
  after
    :ets.delete(:ets_page_preview_test)
  end

  test "Listing failures are reported instead of crashing", %{conn: conn} do
    test_pid = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn _node, _module, _function, _args, _timeout ->
      send(test_pid, :list_requested)
      {:badrpc, :nodedown}
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    assert_receive :list_requested, 1_000
    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Could not list tables"
    assert html =~ "nodedown"
  end

  test "NodeUp/NodeDown refresh the service list", %{conn: conn} do
    fake_node = :myapp@nohost
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:ets_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    assert_receive {:ets_index_pid, ets_index_pid}, 1_000

    send(ets_index_pid, {:nodeup, fake_node})
    send(ets_index_pid, {:nodedown, fake_node})

    :timer.sleep(50)

    assert render(index_live) =~ "Tables:"
  end

  test "Switching the source to Mnesia reports when it is not running", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    :timer.sleep(50)

    index_live
    |> element("#ets-update-form")
    |> render_change(%{
      source: "mnesia",
      service: to_string(Node.self()),
      sort_by: "memory",
      search: ""
    })

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Mnesia is not running on"
    refute html =~ "Could not list tables"
  end

  test "Mnesia source lists tables with storage and previews contents", %{conn: conn} do
    Application.put_env(:observer_web, :table_content_inspection, true)

    :ok = :mnesia.start()

    {:atomic, :ok} =
      :mnesia.create_table(:ets_page_mnesia_test,
        attributes: [:key, :value],
        ram_copies: [node()]
      )

    :ok = :mnesia.dirty_write({:ets_page_mnesia_test, :page_key, "page_value"})

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/ets")

    :timer.sleep(50)

    index_live
    |> element("#ets-update-form")
    |> render_change(%{
      source: "mnesia",
      service: to_string(Node.self()),
      sort_by: "memory",
      search: "ets_page_mnesia_test"
    })

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "STORAGE"
    assert html =~ "ram_copies"
    assert html =~ "ets_page_mnesia_test"

    html =
      index_live
      |> element("#ets-select-row-0")
      |> render_click()

    assert html =~ "storage:"
    assert html =~ "First objects (bounded preview)"
    assert html =~ "page_key"
    assert html =~ "page_value"
  after
    :mnesia.delete_table(:ets_page_mnesia_test)
    :mnesia.stop()
  end
end
