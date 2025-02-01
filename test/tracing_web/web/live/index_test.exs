defmodule Tracing.Web.IndexLiveTest do
  use Tracing.Web.ConnCase, async: false

  import Mox
  alias TracingWeb.Tracer

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup context do
    # Calling this function guarantess that the module is loaded
    TracingWeb.Common.uuid4()

    context
  end

  test "forbidding mount using a resolver callback", %{conn: conn} do
    assert {:error, {:redirect, redirect}} = live(conn, "/tracing-limited")
    assert %{to: "/", flash: %{"error" => "Access forbidden"}} = redirect
  end

  test "GET /tracing", %{conn: conn} do
    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, _index_live, html} = live(conn, "/tracing")

    assert html =~ "Live Tracing"
  end

  test "Add/Remove Local Service + Module + Function + MatchSpec", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

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

  test "Run Trace for module TracingWeb.Common", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-TracingWeb-Common-add-item")
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

    TracingWeb.Common.uuid4()

    html =
      index_live
      |> element("#tracing-multi-select-stop", "STOP")
      |> render_click()

    assert render(index_live) =~ "TracingWeb.Common.uuid4"

    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Run Trace for function TracingWeb.Common.uuid4/0", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-TracingWeb-Common-add-item")
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

    TracingWeb.Common.uuid4()

    :timer.sleep(50)

    assert render(index_live) =~ "TracingWeb.Common.uuid4"
    assert render(index_live) =~ "caller: {Tracing.Web.IndexLive"
  end

  test "Run Trace for mix Elixir.Enum and function TracingWeb.Common.uuid4/0", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-TracingWeb-Common-add-item")
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

    assert render(index_live) =~ "Enum."
  end

  test "Tracing timing out", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-TracingWeb-Common-add-item")
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
    service = String.replace(node, "@", "-")

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-TracingWeb-Common-add-item")
    |> render_click()

    functions = [
      %{
        arity: 2,
        function: :testing_adding_fun,
        match_spec: [],
        module: TracingWeb.TracerFixtures,
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
    service = String.replace(node, "@", "-")
    test_pid_process = self()

    TracingWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:tracing_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, "/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    assert_receive {:tracing_index_pid, tracing_index_pid}, 1_000

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-TracingWeb-Common-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.TracingWeb.Common"

    send(tracing_index_pid, {:nodeup, fake_node})
    send(tracing_index_pid, {:nodedown, fake_node})

    # Check node up/down doesn't change the selected items
    assert html = render(index_live)
    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.TracingWeb.Common"
  end
end
