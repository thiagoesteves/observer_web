defmodule ObserverWeb.Version.ServerTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Version
  alias ObserverWeb.Version.Server

  @table_name :observer_web_versions
  @key :state

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer successfully" do
      assert {:ok, pid} = Server.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "registers the process with the module name" do
      {:ok, _pid} = Server.start_link([])
      assert Process.whereis(Server) != nil
      GenServer.stop(Server)
    end

    test "creates ETS table on initialization" do
      {:ok, _pid} = Server.start_link([])
      assert :ets.whereis(@table_name) != :undefined
      GenServer.stop(Server)
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      {:ok, pid} = Server.start_link([])

      # handle_continue is processed before any later message, so this call is a barrier for it.
      _synchronize = :sys.get_state(pid)

      state = Server.status()
      assert %Server{} = state

      GenServer.stop(pid)
    end

    test "stores initial state in ETS" do
      {:ok, pid} = Server.start_link([])
      _synchronize = :sys.get_state(pid)

      [{_, state}] = :ets.lookup(@table_name, @key)
      assert %Server{} = state

      GenServer.stop(pid)
    end
  end

  describe "status/0" do
    test "returns current state from ETS" do
      {:ok, pid} = Server.start_link([])
      _synchronize = :sys.get_state(pid)

      status = Server.status()
      assert %Server{} = status
      assert status.status in [:ok, :warning, :empty]

      GenServer.stop(Server)
    end

    test "returns empty state when ETS lookup fails" do
      # Don't start server, so ETS table doesn't exist
      status = Server.status()
      assert %Server{status: :empty, local: nil, nodes: nil} = status
    end
  end

  describe "handle_continue(:check_versions, state)" do
    setup do
      # `setup` runs in the test process, so this is the pid to signal back to.
      test_pid = self()

      expect(ObserverWeb.RpcMock, :call, fn
        _node, Application, :spec, [:observer_web, :vsn], _timeout ->
          send(test_pid, :version_rpc)
          ~c"1.0.0"
      end)

      :ok
    end

    test "updates versions on continue" do
      {:ok, pid} = Server.start_link([])

      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)

      status = Version.status()
      assert status.local != nil

      GenServer.stop(pid)
    end

    test "schedules next update" do
      {:ok, pid} = Server.start_link([])

      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)

      # The next :check_versions is scheduled a minute out, so it is still pending here - all
      # this asserts is that scheduling it left the server healthy.
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "version checking logic" do
    test "reports :ok status when all nodes have same version" do
      local = Application.spec(:observer_web, :vsn)
      test_pid = self()

      expect(ObserverWeb.RpcMock, :call, fn
        _node, Application, :spec, [:observer_web, :vsn], _timeout ->
          send(test_pid, :version_rpc)
          local
      end)

      {:ok, pid} = Server.start_link([])

      # The version check runs in a handle_continue; wait for its RPC and synchronize on the
      # server so the ETS state is updated before reading it.
      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)

      status = Version.status()
      assert status.status == :ok
      assert status.local == local |> to_string

      GenServer.stop(Server)
    end

    test "reports :warning status when nodes have different versions" do
      test_pid = self()

      expect(ObserverWeb.RpcMock, :call, fn
        _node, Application, :spec, [:observer_web, :vsn], _timeout ->
          send(test_pid, :version_rpc)
          ~c"0.0.0-not-the-local-version"
      end)

      {:ok, pid} = Server.start_link([])

      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)

      status = Version.status()
      assert status.status == :warning
      assert status.nodes == %{Node.self() => "0.0.0-not-the-local-version"}

      GenServer.stop(Server)
    end

    test "handles RPC errors gracefully" do
      test_pid = self()

      expect(ObserverWeb.RpcMock, :call, fn
        _node, Application, :spec, [:observer_web, :vsn], _timeout ->
          send(test_pid, :version_rpc)
          {:error, :timeout}
      end)

      {:ok, pid} = Server.start_link([])

      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)

      status = Version.status()
      # Should still work, just with fewer nodes in the result
      assert %Server{} = status
      assert status.nodes == %{}

      GenServer.stop(Server)
    end

    test "handles missing application version" do
      # When Application.spec returns nil
      :ok = Application.put_env(:observer_web, :test_mode, true)

      {:ok, pid} = Server.start_link([])

      # handle_continue is processed before any later message, so this call is a barrier for it.
      _synchronize = :sys.get_state(pid)

      status = Version.status()
      assert status.local == "" or is_binary(status.local)

      GenServer.stop(Server)
      Application.delete_env(:observer_web, :test_mode)
    end
  end

  describe "handle_info(:check_versions, state)" do
    test "updates versions periodically" do
      local = Application.spec(:observer_web, :vsn)
      test_pid = self()

      expect(ObserverWeb.RpcMock, :call, 2, fn
        _node, Application, :spec, [:observer_web, :vsn], _timeout ->
          send(test_pid, :version_rpc)
          local
      end)

      {:ok, pid} = Server.start_link([])

      # First check: the handle_continue out of init/1.
      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)
      initial_status = Version.status()

      # Second check: the periodic handle_info, driven directly rather than waiting a minute.
      send(pid, :check_versions)
      assert_receive :version_rpc, 1_000
      _synchronize = :sys.get_state(pid)
      updated_status = Version.status()

      assert initial_status.local != nil
      assert updated_status.local != nil

      GenServer.stop(pid)
    end
  end

  describe "struct type" do
    test "Server struct has correct fields" do
      server = %Server{}
      assert server.status == :empty
      assert server.local == nil
      assert server.nodes == nil
    end

    test "Server struct accepts valid status values" do
      assert %Server{status: :ok}
      assert %Server{status: :warning}
      assert %Server{status: :empty}
    end
  end
end
