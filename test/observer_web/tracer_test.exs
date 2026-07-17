defmodule ObserverWeb.TracerTest do
  use ExUnit.Case, async: true

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias ObserverWeb.Tracer
  alias ObserverWeb.TracerFixtures

  setup :verify_on_exit!

  test "get_modules/1" do
    RpcStubber.defaults()

    assert list = Tracer.get_modules(Node.self())
    assert Enum.member?(list, :kernel)
  end

  test "get_module_functions_info/2" do
    RpcStubber.defaults()

    assert %{
             functions: %{"config_change/3" => %{arity: 3, name: :config_change}},
             module: :kernel,
             node: :nonode@nohost
           } = Tracer.get_module_functions_info(Node.self(), :kernel)

    assert %{
             functions: _,
             module: :erlang,
             node: :nonode@nohost
           } = Tracer.get_module_functions_info(Node.self(), :erlang)
  end

  test "get_default_functions_matchspecs/0" do
    assert %{
             return_trace: %{pattern: [{:_, [], [{:return_trace}]}]},
             exception_trace: %{pattern: [{:_, [], [{:exception_trace}]}]},
             caller: %{pattern: [{:_, [], [{:message, {:caller}}]}]},
             process_dump: %{pattern: [{:_, [], [{:message, {:process_dump}}]}]}
           } = Tracer.get_default_functions_matchspecs()

    # The tool-internal match specs must stay out of this map - the Tracing page renders every
    # key here as a user-facing match-spec option.
    refute Map.has_key?(Tracer.get_default_functions_matchspecs(), :capture_args)
    refute Map.has_key?(Tracer.get_default_functions_matchspecs(), :call_seq)
  end

  test "get_tool_functions_matchspecs/0" do
    assert %{
             capture_args: %{pattern: [{:_, [], [{:message, :"$_"}]}]},
             call_seq: %{pattern: [{:_, [], [{:return_trace}, {:message, :"$_"}]}]}
           } = Tracer.get_tool_functions_matchspecs()
  end

  describe "start_trace/2" do
    test "Only one session is allowed for Tracer" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 1})

      assert {:error, :already_started} =
               Tracer.start_trace(functions, %{max_messages: 1})

      terminate_tracing(session_id)
    end

    test "Success requesting only module" do
      node = Node.self()

      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id} = state} =
               Tracer.start_trace(functions, %{max_messages: 1})

      assert state == Tracer.state()

      run_traced(fn -> TracerFixtures.testing_fun([true, true, true]) end)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :call, msg}, 1_000

      assert msg =~ "TracerFixtures"

      terminate_tracing(session_id)
    end

    test "Success requesting module/function" do
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
               Tracer.start_trace(functions, %{max_messages: 1})

      run_traced(fn -> TracerFixtures.testing_adding_fun(50, 50) end)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :call, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_adding_fun"

      terminate_tracing(session_id)
    end

    test "Success requesting module/function with match_spec [return_trace]" do
      node = Node.self()

      functions = [
        %{
          arity: 2,
          function: :testing_adding_fun,
          match_spec: ["return_trace"],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 2})

      run_traced(fn -> TracerFixtures.testing_adding_fun(253, 200) end)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :return_from, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_adding_fun"
      assert msg =~ "453"

      terminate_tracing(session_id)
    end

    test "Success requesting module/function with match_spec [caller]" do
      node = Node.self()

      functions = [
        %{
          arity: 2,
          function: :testing_adding_fun,
          match_spec: ["caller"],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 2})

      run_traced(fn -> TracerFixtures.testing_adding_fun(255, 200) end)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :call, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_adding_fun"
      # The traced call runs inside a Task (see run_traced/1), so that is the captured caller.
      assert msg =~ "caller: {Task.Supervised"

      terminate_tracing(session_id)
    end

    @tag :capture_log
    test "Success requesting module/function with match_spec [exception_trace]" do
      node = Node.self()

      functions = [
        %{
          arity: 1,
          function: :testing_exception_fun,
          match_spec: ["exception_trace"],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 2})

      spawn(fn ->
        TracerFixtures.testing_exception_fun(0)
      end)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :exception_from, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_exception_fun"
      assert msg =~ "exception_value: {:error, :badarith}"

      terminate_tracing(session_id)
    end
  end

  describe "stop_trace/2" do
    test "Ignore stop_trace with invalid session_id [handle_call]" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 30})

      assert %Tracer{status: :running} = Tracer.state()

      assert :ok == Tracer.stop_trace("123456789")

      assert %Tracer{status: :running} = Tracer.state()

      terminate_tracing(session_id)
    end

    test "Notifies the requester with :stop_tracing when max_messages is reached" do
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
               Tracer.start_trace(functions, %{max_messages: 1})

      run_traced(fn -> TracerFixtures.testing_adding_fun(1, 1) end)

      assert_receive {:new_trace_message, ^session_id, ^node, 1, :call, _msg}, 1_000
      assert_receive {:stop_tracing, ^session_id}, 1_000

      # The session is fully reset, ready for the next one
      assert %Tracer{status: :idle, session_id: nil} = Tracer.state()

      # :dbg needs a moment to settle before the next test starts a new session
      :timer.sleep(50)
    end

    test "Ignore stop_trace with invalid session_id [handle_info]" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 30})

      assert %Tracer{status: :running} = Tracer.state()

      send(ObserverWeb.Tracer.Server, {:stop_tracing, "123456789"})

      assert %Tracer{status: :running} = Tracer.state()

      terminate_tracing(session_id)
    end
  end

  describe "Timeouts" do
    test "Session Timed out" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: _session_id}} =
               Tracer.start_trace(functions, %{max_messages: 30, session_timeout_ms: 50})

      assert_receive {:trace_session_timeout, _session_id}, 1_000
    end

    test "Ignore Timeout messages with invalid ID" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               Tracer.start_trace(functions, %{max_messages: 20})

      assert %Tracer{status: :running} = Tracer.state()

      send(ObserverWeb.Tracer.Server, {:trace_session_timeout, "invalid-session"})

      assert %Tracer{status: :running} = Tracer.state()

      terminate_tracing(session_id)
    end
  end

  test "Request Function terminate" do
    functions = [
      %{
        arity: :_,
        function: :_,
        match_spec: [],
        module: TracerFixtures,
        node: Node.self()
      }
    ]

    test_pid = self()

    spawn(fn ->
      {:ok, %{session_id: session_id}} =
        Tracer.start_trace(functions, %{max_messages: 20})

      send(test_pid, {:trace_started, session_id})
    end)

    # Synchronize on the session actually starting, then wait for the tracer to process the
    # requester's :DOWN and reset - polling idle alone could pass before the session exists.
    assert_receive {:trace_started, _session_id}, 1_000

    assert :ok = wait_until(fn -> match?(%Tracer{status: :idle}, Tracer.state()) end)
  end

  defp terminate_tracing(session_id) do
    :ok = Tracer.stop_trace(session_id)
    :timer.sleep(50)
  end

  defp wait_until(fun, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    wait_until_loop(fun, deadline)
  end

  defp wait_until_loop(fun, deadline) do
    cond do
      fun.() -> :ok
      System.monotonic_time(:millisecond) >= deadline -> :timeout
      true -> tick_and_retry(fun, deadline)
    end
  end

  defp tick_and_retry(fun, deadline) do
    Process.sleep(20)

    wait_until_loop(fun, deadline)
  end

  # Display sessions drop trace events originating from the requesting process itself (the
  # dashboard LiveView in production - see Tracer.Server.handle_trace/2), so traced calls must
  # come from a different process.
  defp run_traced(fun) do
    fun |> Task.async() |> Task.await()
  end
end
