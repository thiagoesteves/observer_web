defmodule Observer.Web.Tracing.PageLiveTest do
  use Observer.Web.ConnCase, async: false

  import Mox
  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber
  alias ObserverWeb.Tracer

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup context do
    # Calling this function guarantess that the module is loaded
    ObserverWeb.Common.uuid4()

    context
  end

  test "GET /tracing - fallback on the default", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer")

    assert html =~ "Live Tracing"
  end

  test "GET /tracing", %{conn: conn} do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, _index_live, html} = live(conn, "/observer/tracing")

    assert html =~ "Live Tracing"
  end

  test "Add/Remove Local Service + Module + Function + MatchSpec", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-map-2-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-match_spec-caller-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.Enum"
    assert html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-services-#{service}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "modules:Elixir.Enum"
    assert html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-Enum-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "modules:Elixir.Enum"
    assert html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-functions-map-2-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "modules:Elixir.Enum"
    refute html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-match_spec-caller-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "modules:Elixir.Enum"
    refute html =~ "functions:map/2"
    refute html =~ "match_spec:caller"
  end

  test "Filtering by Module", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
      |> render_click()

    assert html =~ "Elixir.Agent"

    html =
      index_live
      |> element("#multi-select-list-search-form-tracing-multi-select-modules")
      |> render_change(%{"_target" => "modules", "modules" => "Enum"})

    refute html =~ "Elixir.Agent"
  end

    test "Filtering by Module non sensitive", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
      |> render_click()

    assert html =~ "Elixir.Agent"

    html =
      index_live
      |> element("#multi-select-list-search-form-tracing-multi-select-modules")
      |> render_change(%{"_target" => "modules", "modules" => "agent"})

    assert html =~ "Elixir.Agent"
  end

  test "Filtering by Function", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-functions-map-2-add-item")
      |> render_click()

    assert html =~ "all?"

    html =
      index_live
      |> element("#multi-select-list-search-form-tracing-multi-select-modules")
      |> render_change(%{"_target" => "functions", "functions" => "map"})

    refute html =~ "all?"
  end

  test "Run Trace for module ObserverWeb.Common", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-ObserverWeb-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-update-form")
    |> render_change(%{max_messages: 1_000, session_timeout_seconds: 30})

    html =
      index_live
      |> element("#tracing-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    ObserverWeb.Common.uuid4()

    html =
      index_live
      |> element("#tracing-multi-select-stop", "STOP")
      |> render_click()

    assert render(index_live) =~ "ObserverWeb.Common.uuid4"

    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Run Trace for function ObserverWeb.Common.uuid4/0", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-ObserverWeb-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-uuid4-0-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-match_spec-caller-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    ObserverWeb.Common.uuid4()

    :timer.sleep(50)

    assert render(index_live) =~ "ObserverWeb.Common.uuid4"
    assert render(index_live) =~ "caller: {Observer.Web.Tracing.PageLiveTest"
  end

  test "Run Trace for mix Elixir.Enum and function ObserverWeb.Common.uuid4/0", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-ObserverWeb-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-uuid4-0-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-match_spec-caller-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-run", "RUN")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-stop", "STOP")
    |> render_click()
  end

  test "Observer timing out", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-ObserverWeb-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-uuid4-0-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-match_spec-caller-add-item")
    |> render_click()

    index_live
    |> element("#tracing-update-form")
    |> render_change(%{max_messages: 5, session_timeout_seconds: 0})

    index_live
    |> element("#tracing-multi-select-run", "RUN")
    |> render_click()

    :timer.sleep(50)

    assert html = render(index_live)
    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Try to RUN tracing when it is already running", %{conn: conn} do
    node = Node.self() |> to_string
    service = Helpers.normalize_id(node)

    RpcStubber.defaults()
    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-ObserverWeb-Common-add-item")
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
             Tracer.start_trace(functions, %{max_messages: 1})

    index_live
    |> element("#tracing-multi-select-run", "RUN")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-toggle-options")
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
      send(test_pid_process, {:tracing_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)

    TelemetryStubber.defaults()

    {:ok, index_live, _html} = live(conn, "/observer/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    assert_receive {:tracing_index_pid, tracing_index_pid}, 1_000

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-ObserverWeb-Common-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.ObserverWeb.Common"

    send(tracing_index_pid, {:nodeup, fake_node})
    send(tracing_index_pid, {:nodedown, fake_node})

    # Check node up/down doesn't change the selected items
    assert html = render(index_live)
    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.ObserverWeb.Common"
  end
end
