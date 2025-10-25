defmodule ObserverWeb.Monitor.ProcessPort do
  @moduledoc """
  This module contains the reporting functions for Beam VM
  """

  import Telemetry.Metrics

  use GenServer

  alias ObserverWeb.Apps
  alias ObserverWeb.Telemetry.Consumer

  @default_poll_interval 1_000

  @type t :: %__MODULE__{
          event: String.t(),
          metric: String.t(),
          metric_summary: map(),
          atomized_id: atom()
        }

  defstruct [:event, :metric, :metric_summary, :atomized_id]

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
      Application.get_env(:observer_web, :beam_vm_poller_interval_ms) || @default_poll_interval

    :timer.send_interval(poll_interval, :refresh_metrics)

    {:ok, %{}}
  end

  @impl true
  def handle_call({:id_info, pid_or_port}, _from, monitored_ids) do
    case monitored_ids[pid_or_port] do
      nil ->
        {:reply, {:error, :not_found}, monitored_ids}

      info ->
        {:reply, {:ok, info}, monitored_ids}
    end
  end

  def handle_call({:attach_id, pid_or_port}, _from, monitored_ids) do
    case monitored_ids[pid_or_port] do
      nil ->
        id_info = id_to_struct(pid_or_port)

        :telemetry.attach(
          {__MODULE__, id_info.event, self()},
          id_info.event,
          &Consumer.handle_event/4,
          {[id_info.metric_summary], nil, Node.self()}
        )

        {:reply, {:ok, id_info}, Map.put(monitored_ids, pid_or_port, id_info)}

      info ->
        # Already in the list of monitored ids
        {:reply, {:ok, info}, monitored_ids}
    end
  end

  def handle_call({:detach_id, pid_or_port}, _from, monitored_ids) do
    case monitored_ids[pid_or_port] do
      nil ->
        {:reply, :ok, monitored_ids}

      info ->
        # Add a gap in the chart to indicate that data sending was disabled
        :telemetry.execute(info.event, empty_memory_data(pid_or_port), %{})

        # Detach the telemetry handler
        :telemetry.detach({__MODULE__, info.event, self()})

        {:reply, :ok, Map.drop(monitored_ids, [pid_or_port])}
    end
  end

  @impl true
  def handle_info(:refresh_metrics, monitored_ids) do
    updated_monitored_ids =
      Enum.reduce(monitored_ids, %{}, fn
        {pid, process_info}, acc when is_pid(pid) ->
          case Apps.Process.info(pid) do
            %Apps.Process{memory: memory} ->
              :telemetry.execute(
                process_info.event,
                Map.merge(empty_memory_data(pid), memory),
                %{}
              )

              Map.put(acc, pid, process_info)

            :undefined ->
              # NOTE: The process is either dead or not available (remove)
              :telemetry.detach({__MODULE__, process_info.event, self()})

              acc
          end

        {port, port_info}, acc when is_port(port) ->
          case Apps.Port.info(port) do
            %Apps.Port{memory: memory} ->
              :telemetry.execute(port_info.event, %{total: memory}, %{})

              Map.put(acc, port, port_info)

            :undefined ->
              # NOTE: The port is either dead or not available (remove)
              :telemetry.detach({__MODULE__, port_info.event, self()})

              acc
          end
      end)

    {:noreply, updated_monitored_ids}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec start_id_monitor(pid_or_port :: pid() | port()) :: {:ok, __MODULE__.t()}
  def start_id_monitor(pid_or_port) do
    target_node = node(pid_or_port)
    GenServer.call({__MODULE__, target_node}, {:attach_id, pid_or_port})
  end

  @spec stop_id_monitor(pid_or_port :: pid() | port()) :: :ok
  def stop_id_monitor(pid_or_port) do
    target_node = node(pid_or_port)

    try do
      GenServer.call({__MODULE__, target_node}, {:detach_id, pid_or_port})
    catch
      _, _ ->
        :ok
    end
  end

  @spec id_info(pid_or_port :: pid() | port()) :: {:ok, map} | {:error, :not_found | :rescued}
  def id_info(pid_or_port) do
    target_node = node(pid_or_port)

    try do
      GenServer.call({__MODULE__, target_node}, {:id_info, pid_or_port})
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
  defp empty_memory_data(pid) when is_pid(pid) do
    %{
      total: nil,
      stack_and_heap: nil,
      heap_size: nil,
      stack_size: nil,
      gc_min_heap_size: nil,
      gc_full_sweep_after: nil
    }
  end

  defp empty_memory_data(port) when is_port(port), do: %{total: nil}

  defp id_to_struct(pid) when is_pid(pid) do
    atomized_id =
      pid
      |> inspect()
      |> String.replace(["#PID<"], "pid_")
      |> String.replace(["."], "_")
      |> String.replace([">"], "")
      |> String.to_atom()

    event = [:vm, :process, :memory, atomized_id]
    metric = (event ++ [:total]) |> Enum.join(".")
    metric_summary = summary(metric)

    %__MODULE__{
      event: event,
      metric: metric,
      metric_summary: metric_summary,
      atomized_id: atomized_id
    }
  end

  defp id_to_struct(port) when is_port(port) do
    atomized_id =
      port
      |> inspect()
      |> String.replace(["#Port<"], "port_")
      |> String.replace(["."], "_")
      |> String.replace([">"], "")
      |> String.to_atom()

    event = [:vm, :port, :memory, atomized_id]
    metric = (event ++ [:total]) |> Enum.join(".")
    metric_summary = summary(metric)

    %__MODULE__{
      event: event,
      metric: metric,
      metric_summary: metric_summary,
      atomized_id: atomized_id
    }
  end
end
