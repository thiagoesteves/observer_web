defmodule ObserverWeb.Tracer.ToolDurationIntegrationTest do
  @moduledoc """
  Exercises `ObserverWeb.Tracer.start_trace/2` end-to-end with `tool: :duration`, in particular
  that `return_trace` is forced into the match spec automatically even though the caller passes
  `match_spec: []` (the Profiling page has no match-spec picker of its own).

  Kept `async: false` and separate from `ObserverWeb.TracerTest`: `ObserverWeb.Tracer.Server` and
  `:dbg` are both global singletons, so running this alongside other tests that drive real tracing
  sessions concurrently (async: true) risks flaky cross-test interference.
  """
  use ExUnit.Case, async: false

  alias ObserverWeb.Tracer
  alias ObserverWeb.TracerFixtures

  # NOTE: :dbg needs a moment to settle after a session stops (via the max_messages cap here)
  # before the next test's :dbg.tracer/2 call, or the dbg server itself crashes.
  setup do
    on_exit(fn -> :timer.sleep(50) end)
  end

  test "return_trace is forced in, so duration is measured even with an empty match_spec" do
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
             Tracer.start_trace(functions, %{max_messages: 2, tool: :duration})

    TracerFixtures.testing_adding_fun(1, 1)

    assert_receive {:tool_report, ^session_id, report}, 1_000
    assert [{{^node, TracerFixtures, :testing_adding_fun, 2, nil}, duration}] = report
    assert is_integer(duration) and duration >= 0
  end

  test "reports one row per call when no aggregation mode is selected" do
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
             Tracer.start_trace(functions, %{max_messages: 4, tool: :duration})

    TracerFixtures.testing_adding_fun(1, 1)
    TracerFixtures.testing_adding_fun(2, 2)

    assert_receive {:tool_report, ^session_id, report}, 1_000

    assert [
             {{^node, TracerFixtures, :testing_adding_fun, 2, nil}, _},
             {{^node, TracerFixtures, :testing_adding_fun, 2, nil}, _}
           ] = report
  end

  test "reduces samples when an aggregation mode is selected" do
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
               max_messages: 4,
               tool: :duration,
               tool_opts: %{aggregation: :sum}
             })

    TracerFixtures.testing_adding_fun(1, 1)
    TracerFixtures.testing_adding_fun(2, 2)

    assert_receive {:tool_report, ^session_id, report}, 1_000
    assert [{{^node, TracerFixtures, :testing_adding_fun, 2, nil}, sum}] = report
    assert is_integer(sum) and sum >= 0
  end
end
