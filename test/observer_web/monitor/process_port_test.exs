defmodule ObserverWeb.Monitor.ProcessPortTest do
  use ExUnit.Case, async: false

  alias ObserverWeb.Monitor
  alias ObserverWeb.Monitor.ProcessPort

  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  setup do
    # Clear any existing telemetry handlers
    on_exit(fn ->
      :telemetry.list_handlers([])
      |> Enum.each(fn %{id: id} -> :telemetry.detach(id) end)
    end)

    ObserverWeb.TelemetryMock
    |> stub(:push_data, fn _event -> :ok end)

    ObserverWeb.RpcMock
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer with default config" do
      pid = Process.whereis(ProcessPort)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "start_id_monitor/1 and stop_id_monitor/1" do
    test "monitors a process and returns process info" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, info} = Monitor.start_id_monitor(test_pid)

      assert %ProcessPort{} = info
      assert info.event == [:vm, :process, :memory, info.atomized_id]
      assert is_atom(info.atomized_id)
      assert String.starts_with?(Atom.to_string(info.atomized_id), "pid_")
      assert info.metric == Enum.join(info.event ++ [:total], ".")

      # Clean up
      Process.exit(test_pid, :kill)
      Monitor.stop_id_monitor(test_pid)
    end

    test "monitors a port and returns port info" do
      {:ok, port} = :gen_tcp.listen(0, [])

      {:ok, info} = Monitor.start_id_monitor(port)

      assert %ProcessPort{} = info
      assert info.event == [:vm, :port, :memory, info.atomized_id]
      assert is_atom(info.atomized_id)
      assert String.starts_with?(Atom.to_string(info.atomized_id), "port_")
      assert info.metric == Enum.join(info.event ++ [:total], ".")

      # Clean up
      :gen_tcp.close(port)
      Monitor.stop_id_monitor(port)
    end

    test "returns same info when attaching same process twice" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, info1} = Monitor.start_id_monitor(test_pid)
      {:ok, info2} = Monitor.start_id_monitor(test_pid)

      assert info1 == info2

      # Clean up
      Process.exit(test_pid, :kill)
      Monitor.stop_id_monitor(test_pid)
    end

    test "stops monitoring a process" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, _info} = Monitor.start_id_monitor(test_pid)
      assert :ok = Monitor.stop_id_monitor(test_pid)

      # Verify it's no longer monitored
      assert {:error, :not_found} = Monitor.id_info(test_pid)

      # Clean up
      Process.exit(test_pid, :kill)
    end

    test "stop_id_monitor returns :ok even if process not monitored" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      assert :ok = Monitor.stop_id_monitor(test_pid)

      # Clean up
      Process.exit(test_pid, :kill)
    end

    test "stop_id_monitor handles errors gracefully" do
      # Create a fake PID that doesn't exist on this node
      fake_pid = :erlang.list_to_pid(~c"<0.999999.0>")

      assert :ok = Monitor.stop_id_monitor(fake_pid)
    end
  end

  describe "id_info/1" do
    test "returns process info for monitored process" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, expected_info} = Monitor.start_id_monitor(test_pid)
      {:ok, retrieved_info} = Monitor.id_info(test_pid)

      assert retrieved_info == expected_info

      # Clean up
      Process.exit(test_pid, :kill)
      Monitor.stop_id_monitor(test_pid)
    end

    test "returns error for non-monitored process" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      assert {:error, :not_found} = Monitor.id_info(test_pid)

      # Clean up
      Process.exit(test_pid, :kill)
    end

    test "returns error when Pid is not present" do
      # Create a fake PID on a non-existent node
      fake_pid = :erlang.list_to_pid(~c"<0.999999.0>")

      assert {:error, :not_found} = Monitor.id_info(fake_pid)
    end
  end

  describe "handle_info(:refresh_metrics, _)" do
    test "removes dead processes from monitoring" do
      test_pid = spawn(fn -> :ok end)
      # Ensure process dies
      Process.sleep(10)

      {:ok, _info} = Monitor.start_id_monitor(test_pid)

      # Trigger refresh - should detect dead process
      send(Process.whereis(ProcessPort), :refresh_metrics)
      Process.sleep(100)

      # Process should no longer be in monitored list
      assert {:error, :not_found} = Monitor.id_info(test_pid)
    end

    test "updates metrics for monitored ports" do
      {:ok, port} = :gen_tcp.listen(0, [])

      {:ok, _info} = Monitor.start_id_monitor(port)

      # Trigger refresh manually
      send(Process.whereis(ProcessPort), :refresh_metrics)
      Process.sleep(100)

      # Port should still be monitored
      assert {:ok, _info} = Monitor.id_info(port)

      # Clean up
      :gen_tcp.close(port)
      Monitor.stop_id_monitor(port)
    end

    test "removes closed ports from monitoring" do
      {:ok, port} = :gen_tcp.listen(0, [])
      {:ok, _info} = Monitor.start_id_monitor(port)

      # Close the port
      :gen_tcp.close(port)

      # Trigger refresh - should detect closed port
      send(Process.whereis(ProcessPort), :refresh_metrics)
      Process.sleep(100)

      # Port should no longer be in monitored list
      assert {:error, :not_found} = Monitor.id_info(port)
    end
  end

  describe "id_to_struct/1 for PIDs" do
    test "converts PID to proper struct format" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, info} = Monitor.start_id_monitor(test_pid)
      atomized_id = info.atomized_id

      # Check atomized_id format
      atomized_str = Atom.to_string(atomized_id)
      assert String.starts_with?(atomized_str, "pid_")
      refute String.contains?(atomized_str, "#PID<")
      refute String.contains?(atomized_str, ">")
      refute String.contains?(atomized_str, ".")

      # Check event structure
      assert [:vm, :process, :memory, ^atomized_id] = info.event

      # Check metric structure
      assert String.starts_with?(info.metric, "vm.process.memory.")
      assert String.ends_with?(info.metric, ".total")

      # Clean up
      Process.exit(test_pid, :kill)
      Monitor.stop_id_monitor(test_pid)
    end
  end

  describe "id_to_struct/1 for Ports" do
    test "converts Port to proper struct format" do
      {:ok, port} = :gen_tcp.listen(0, [])

      {:ok, info} = Monitor.start_id_monitor(port)
      atomized_id = info.atomized_id

      # Check atomized_id format
      atomized_str = Atom.to_string(atomized_id)
      assert String.starts_with?(atomized_str, "port_")
      refute String.contains?(atomized_str, "#Port<")
      refute String.contains?(atomized_str, ">")
      refute String.contains?(atomized_str, ".")

      # Check event structure
      assert [:vm, :port, :memory, ^atomized_id] = info.event

      # Check metric structure
      assert String.starts_with?(info.metric, "vm.port.memory.")
      assert String.ends_with?(info.metric, ".total")

      # Clean up
      :gen_tcp.close(port)
      Monitor.stop_id_monitor(port)
    end
  end

  describe "telemetry integration" do
    test "attaches telemetry handler when monitoring starts" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      initial_handlers = :telemetry.list_handlers([])
      {:ok, _info} = Monitor.start_id_monitor(test_pid)
      final_handlers = :telemetry.list_handlers([])

      # Should have one more handler
      assert length(final_handlers) == length(initial_handlers) + 1

      # Clean up
      Process.exit(test_pid, :kill)
      Monitor.stop_id_monitor(test_pid)
    end

    test "detaches telemetry handler when monitoring stops" do
      test_pid = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, info} = Monitor.start_id_monitor(test_pid)
      handlers_before = :telemetry.list_handlers([])

      Monitor.stop_id_monitor(test_pid)
      handlers_after = :telemetry.list_handlers([])

      # Should have one fewer handler
      assert length(handlers_after) == length(handlers_before) - 1

      # Verify handler is removed
      handler =
        Enum.find(handlers_after, fn h ->
          h.id == {ProcessPort, info.event, self()}
        end)

      assert handler == nil

      # Clean up
      Process.exit(test_pid, :kill)
    end
  end
end
