defmodule ObserverWeb.Tracer.ToolFlameGraphIntegrationTest do
  @moduledoc """
  Exercises `ObserverWeb.Tracer.start_trace/2` end-to-end with `tool: :flame_graph`, in particular
  that wildcarding function/arity (`:_`) traces every call in the module without needing a
  match spec, and that `:return_to` correctly unwinds the stack.

  Kept `async: false` and separate from `ObserverWeb.TracerTest`: `ObserverWeb.Tracer.Server` and
  `:dbg` are both global singletons, so running this alongside other tests that drive real tracing
  sessions concurrently (async: true) risks flaky cross-test interference.
  """
  use ExUnit.Case, async: false

  alias ObserverWeb.Tracer
  alias ObserverWeb.TracerFixtures.Callee

  # NOTE: :dbg needs a moment to settle after a session stops before the next test's
  # :dbg.tracer/2 call, or the dbg server itself crashes.
  setup do
    on_exit(fn -> :timer.sleep(50) end)
  end

  test "reports time spent per call stack for every function in the traced module" do
    node = Node.self()

    functions = [
      %{arity: :_, function: :_, match_spec: [], module: Callee, node: node}
    ]

    assert {:ok, %{session_id: session_id}} =
             Tracer.start_trace(functions, %{max_messages: 100, tool: :flame_graph})

    Callee.add(2, 3)
    :timer.sleep(50)

    assert :ok = Tracer.stop_trace(session_id)

    assert_receive {:tool_report, ^session_id, report}, 1_000

    assert [%{name: name, value: value, children: children}] = report
    assert name =~ inspect(self())
    assert value > 0

    assert [%{name: "ObserverWeb.TracerFixtures.Callee.add/2", value: ^value, children: []}] =
             children
  end
end
