defmodule Observer.Web.Profiling.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox
  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.Tracer
  alias ObserverWeb.TracerFixtures.Callee

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup context do
    # Calling this function guarantees that the module is loaded
    ObserverWeb.TracerFixtures.testing_fun([])

    context
  end

  test "GET /profiling", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer/profiling")

    assert html =~ "Count Results" or html =~ "Select functions to trace"
  end

  test "Add/Remove Local Service + Module + Function", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    html =
      index_live
      |> element("#profiling-multi-select-functions-testing_adding_fun-2-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.ObserverWeb.TracerFixtures"
    assert html =~ "functions:testing_adding_fun/2"

    html =
      index_live
      |> element("#profiling-multi-select-functions-testing_adding_fun-2-remove-item")
      |> render_click()

    refute html =~ "functions:testing_adding_fun/2"
  end

  test "Run Count for ObserverWeb.TracerFixtures.testing_adding_fun/2", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-functions-testing_adding_fun-2-add-item")
    |> render_click()

    index_live
    |> element("#profiling-update-form")
    |> render_change(%{max_messages: 1, session_timeout_seconds: 30})

    html =
      index_live
      |> element("#profiling-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    ObserverWeb.TracerFixtures.testing_adding_fun(1, 1)

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Count Results"
    assert html =~ "SERVICE"
    assert html =~ node
    assert html =~ "TracerFixtures.testing_adding_fun/2"
    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Switching to Duration shows the aggregation picker", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    html =
      index_live
      |> element("#profiling-update-form")
      |> render_change(%{tool: "duration", max_messages: 1_000, session_timeout_seconds: 30})

    assert html =~ "Aggregation"

    html =
      index_live
      |> element("#profiling-update-form")
      |> render_change(%{tool: "count", max_messages: 1_000, session_timeout_seconds: 30})

    refute html =~ "Aggregation"
  end

  test "Run Duration for ObserverWeb.TracerFixtures.testing_adding_fun/2", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-functions-testing_adding_fun-2-add-item")
    |> render_click()

    index_live
    |> element("#profiling-update-form")
    |> render_change(%{
      tool: "duration",
      aggregation: "sum",
      max_messages: 2,
      session_timeout_seconds: 30
    })

    html =
      index_live
      |> element("#profiling-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    ObserverWeb.TracerFixtures.testing_adding_fun(1, 1)

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Duration Results"
    assert html =~ "TracerFixtures.testing_adding_fun/2"
    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Duration with :dist aggregation renders readable µs ranges instead of a raw map", %{
    conn: conn
  } do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-functions-testing_adding_fun-2-add-item")
    |> render_click()

    index_live
    |> element("#profiling-update-form")
    |> render_change(%{
      tool: "duration",
      aggregation: "dist",
      max_messages: 2,
      session_timeout_seconds: 30
    })

    index_live
    |> element("#profiling-multi-select-run", "RUN")
    |> render_click()

    ObserverWeb.TracerFixtures.testing_adding_fun(1, 1)

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "µs:"
    refute html =~ "%{"
  end

  test "Run Call Sequence for a nested call across two modules", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    # Calling this function guarantees the callee module is loaded
    Callee.add(0, 0)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    index_live
    |> element(
      "#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-Callee-add-item"
    )
    |> render_click()

    index_live
    |> element("#profiling-multi-select-functions-testing_nested_fun-2-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-functions-add-2-add-item")
    |> render_click()

    index_live
    |> element("#profiling-update-form")
    |> render_change(%{tool: "call_seq", max_messages: 4, session_timeout_seconds: 30})

    html =
      index_live
      |> element("#profiling-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    ObserverWeb.TracerFixtures.testing_nested_fun(2, 3)

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Call Sequence Results"
    assert html =~ "TracerFixtures.testing_nested_fun/2"
    assert html =~ "TracerFixtures.Callee.add/2"
    assert html =~ "→"
    assert html =~ "←"
    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Run Flame Graph for every call in a module", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element(
      "#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-Callee-add-item"
    )
    |> render_click()

    index_live
    |> element("#profiling-update-form")
    |> render_change(%{tool: "flame_graph", max_messages: 2, session_timeout_seconds: 30})

    html =
      index_live
      |> element("#profiling-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    Callee.add(2, 3)

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Flame Graph Results"
    assert html =~ "profiling-flame-graph-chart"
    assert html =~ "TracerFixtures.Callee.add/2"
    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Stop button reports the count collected so far", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-functions-testing_adding_fun-2-add-item")
    |> render_click()

    index_live
    |> element("#profiling-update-form")
    |> render_change(%{max_messages: 1_000, session_timeout_seconds: 30})

    index_live
    |> element("#profiling-multi-select-run", "RUN")
    |> render_click()

    ObserverWeb.TracerFixtures.testing_adding_fun(2, 3)
    :timer.sleep(50)

    index_live
    |> element("#profiling-multi-select-stop", "STOP")
    |> render_click()

    :timer.sleep(50)

    html = render(index_live)
    assert html =~ "Count Results"
    assert html =~ "TracerFixtures.testing_adding_fun/2"
  end

  test "Try to RUN when it is already running", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
    |> render_click()

    functions = [
      %{
        arity: 2,
        function: :testing_adding_fun,
        match_spec: [],
        module: ObserverWeb.TracerFixtures,
        node: Node.self()
      }
    ]

    assert {:ok, %{session_id: session_id}} =
             Tracer.start_trace(functions, %{max_messages: 1, tool: :count})

    index_live
    |> element("#profiling-multi-select-run", "RUN")
    |> render_click()

    html =
      index_live
      |> element("#profiling-multi-select-toggle-options")
      |> render_click()

    assert html =~ "IN USE"
    refute html =~ "START"

    Tracer.stop_trace(session_id)
  end

  test "Testing NodeUp/NodeDown", %{conn: conn} do
    fake_node = :myapp@nohost
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:profiling_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/profiling")

    index_live
    |> element("#profiling-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#profiling-multi-select-services-#{service}-add-item")
    |> render_click()

    assert_receive {:profiling_index_pid, profiling_index_pid}, 1_000

    html =
      index_live
      |> element("#profiling-multi-select-modules-Elixir-ObserverWeb-TracerFixtures-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.ObserverWeb.TracerFixtures"

    send(profiling_index_pid, {:nodeup, fake_node})
    send(profiling_index_pid, {:nodedown, fake_node})

    assert html = render(index_live)
    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.ObserverWeb.TracerFixtures"
  end
end
