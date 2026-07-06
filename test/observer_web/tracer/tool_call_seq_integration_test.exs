defmodule ObserverWeb.Tracer.ToolCallSeqIntegrationTest do
  @moduledoc """
  Exercises `ObserverWeb.Tracer.start_trace/2` end-to-end with `tool: :call_seq`, in particular
  that the combined `call_seq` match spec (forced in automatically) delivers both `:return_from`
  events and captured arguments from a single clause.

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

  test "reports a nested call sequence with arguments and return values" do
    node = Node.self()

    functions = [
      %{
        arity: 2,
        function: :testing_nested_fun,
        match_spec: [],
        module: TracerFixtures,
        node: node
      },
      %{
        arity: 2,
        function: :add,
        match_spec: [],
        module: TracerFixtures.Callee,
        node: node
      }
    ]

    assert {:ok, %{session_id: session_id}} =
             Tracer.start_trace(functions, %{max_messages: 4, tool: :call_seq})

    TracerFixtures.testing_nested_fun(2, 3)

    assert_receive {:tool_report, ^session_id, report}, 1_000

    assert [
             %{
               node: ^node,
               type: :enter,
               mod: TracerFixtures,
               fun: :testing_nested_fun,
               depth: 0
             },
             %{node: ^node, type: :enter, mod: TracerFixtures.Callee, fun: :add, depth: 1},
             %{node: ^node, type: :exit, mod: TracerFixtures.Callee, fun: :add, depth: 1},
             %{node: ^node, type: :exit, mod: TracerFixtures, fun: :testing_nested_fun, depth: 0}
           ] = report

    [enter_outer, enter_inner, exit_inner, exit_outer] = report

    assert enter_outer.detail == [2, 3]
    assert enter_inner.detail == [2, 3]
    assert exit_inner.detail == 5
    assert exit_outer.detail == 5
  end
end
