defmodule ObserverWeb.Monitor.Process do
  @moduledoc """
  This module contains the reporting functions for Beam VM
  """

  import Telemetry.Metrics

  use GenServer

  alias ObserverWeb.Telemetry.Consumer

  @default_poll_interval 1_000

  @type t :: %__MODULE__{
          event: String.t(),
          metric: String.t(),
          metric_summary: map(),
          atomized_pid: atom()
        }

  defstruct [:event, :metric, :metric_summary, :atomized_pid]

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    poll_interval =
      Application.get_env(:observer_web, ObserverWeb.Telemetry)[:beam_vm_poller_interval_ms] ||
        @default_poll_interval

    :timer.send_interval(poll_interval, :refresh_metrics)

    {:ok, %{}}
  end

  @impl true
  def handle_call({:enabled?, pid}, _from, monitored_processes) do
    case monitored_processes[pid] do
      nil ->
        {:reply, false, monitored_processes}

      _atomized_pid ->
        {:reply, true, monitored_processes}
    end
  end

  @impl true
  def handle_cast({:attach_process_pid, pid}, monitored_processes) do
    case monitored_processes[pid] do
      nil ->
        process = pid_to_struct(pid)

        :telemetry.attach(
          {__MODULE__, process.event, self()},
          process.event,
          &Consumer.handle_event/4,
          {[process.metric_summary], nil, Node.self()}
        )

        {:noreply, Map.put(monitored_processes, pid, process)}

      _atomized_pid ->
        # Already in the list of monitored processes
        {:noreply, monitored_processes}
    end
  end

  def handle_cast({:detach_process_pid, pid}, monitored_processes) do
    case monitored_processes[pid] do
      nil ->
        {:noreply, monitored_processes}

      process ->
        # Add a gap in the chart to indicate that data sending was disabled
        :telemetry.execute(
          [:vm, :process, :memory, process.atomized_pid],
          empty_memory_data(),
          %{}
        )

        # Detach the telemetry handler
        :telemetry.detach({__MODULE__, process.event, self()})

        {:noreply, Map.drop(monitored_processes, [pid])}
    end
  end

  @impl true
  def handle_info(:refresh_metrics, monitored_processes) do
    updated_monitored_processes =
      Enum.reduce(monitored_processes, %{}, fn {pid, process}, acc ->
        case ObserverWeb.Apps.Process.info(pid) do
          %{memory: memory} ->
            :telemetry.execute(
              [:vm, :process, :memory, process.atomized_pid],
              Map.merge(empty_memory_data(), memory),
              %{}
            )

            Map.put(acc, pid, process)

          _ ->
            # NOTE: The process is either dead or not available (remove)
            :telemetry.detach({__MODULE__, process.event, self()})

            acc
        end
      end)

    {:noreply, updated_monitored_processes}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec start_process_monitor(pid :: pid()) :: :ok
  def start_process_monitor(pid) do
    target_node = node(pid)
    GenServer.cast({__MODULE__, target_node}, {:attach_process_pid, pid})
  end

  @spec stop_process_monitor(pid :: pid()) :: :ok
  def stop_process_monitor(pid) do
    target_node = node(pid)
    GenServer.cast({__MODULE__, target_node}, {:detach_process_pid, pid})
  end

  @spec enabled?(pid :: pid()) :: boolean()
  def enabled?(pid) do
    target_node = node(pid)
    GenServer.call({__MODULE__, target_node}, {:enabled?, pid})
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
  defp empty_memory_data do
    %{
      total: nil,
      stack_and_heap: nil,
      heap_size: nil,
      stack_size: nil,
      gc_min_heap_size: nil,
      gc_full_sweep_after: nil
    }
  end

  defp pid_to_struct(pid) do
    atomized_pid =
      pid
      |> inspect()
      |> String.replace(["#PID<"], "pid_")
      |> String.replace(["."], "_")
      |> String.replace([">"], "")
      |> String.to_atom()

    event = [:vm, :process, :memory, atomized_pid]
    metric = (event ++ [:total]) |> Enum.join(".")
    metric_summary = summary(metric)

    %__MODULE__{
      event: event,
      metric: metric,
      metric_summary: metric_summary,
      atomized_pid: atomized_pid
    }
  end
end
