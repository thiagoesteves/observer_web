defmodule ObserverWeb.Tracer.ToolCountIntegrationTest do
  @moduledoc """
  Exercises `ObserverWeb.Tracer.start_trace/2` end-to-end with `tool: :count`, across the three
  ways a session can end (max_messages reached, explicit stop, timeout).

  Kept `async: false` and separate from `ObserverWeb.TracerTest`: `ObserverWeb.Tracer.Server` and
  `:dbg` are both global singletons, so running this alongside other tests that drive real tracing
  sessions concurrently (async: true) risks flaky cross-test interference.
  """
  use ExUnit.Case, async: false

  alias ObserverWeb.Tracer
  alias ObserverWeb.TracerFixtures

  # NOTE: :dbg needs a moment to settle after a session stops before the next test's
  # :dbg.tracer/2 call, or the dbg server itself crashes.
  setup do
    on_exit(fn -> :timer.sleep(50) end)
  end

  test "reports aggregated counts when max_messages is reached" do
    node = Node.self()

    functions = [
      %{
        arity: 2,
        function: :testing_adding_fun,
        match_spec: [],
        module: TracerFixtures,
        node: node
      }
    ]

    assert {:ok, %{session_id: session_id}} =
             Tracer.start_trace(functions, %{max_messages: 2, tool: :count})

    TracerFixtures.testing_adding_fun(1, 1)
    TracerFixtures.testing_adding_fun(2, 2)

    assert_receive {:tool_report, ^session_id, report}, 1_000
    assert [{{^node, TracerFixtures, :testing_adding_fun, 2, nil}, 2}] = report

    assert_receive {:stop_tracing, ^session_id}, 1_000
    refute_receive {:new_trace_message, _, _, _, _, _}
  end

  test "reports aggregated counts on explicit stop_trace/1" do
    node = Node.self()

    functions = [
      %{
        arity: 2,
        function: :testing_adding_fun,
        match_spec: [],
        module: TracerFixtures,
        node: node
      }
    ]

    assert {:ok, %{session_id: session_id}} =
             Tracer.start_trace(functions, %{max_messages: 30, tool: :count})

    TracerFixtures.testing_adding_fun(1, 1)
    :timer.sleep(50)

    assert :ok = Tracer.stop_trace(session_id)

    assert_receive {:tool_report, ^session_id, report}, 1_000
    assert [{{^node, TracerFixtures, :testing_adding_fun, 2, nil}, 1}] = report
  end

  test "reports aggregated counts on session timeout" do
    node = Node.self()

    functions = [
      %{
        arity: 2,
        function: :testing_adding_fun,
        match_spec: [],
        module: TracerFixtures,
        node: node
      }
    ]

    assert {:ok, %{session_id: session_id}} =
             Tracer.start_trace(functions, %{
               max_messages: 30,
               tool: :count,
               session_timeout_ms: 50
             })

    TracerFixtures.testing_adding_fun(1, 1)

    assert_receive {:tool_report, ^session_id, report}, 1_000
    assert [{{^node, TracerFixtures, :testing_adding_fun, 2, nil}, 1}] = report

    assert_receive {:trace_session_timeout, ^session_id}, 1_000
  end
end
