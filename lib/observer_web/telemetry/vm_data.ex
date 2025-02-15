defmodule ObserverWeb.Telemetry.VmData do
  @moduledoc """
  GenServer that collects the vm metrics and produce its statistics
  """
  use GenServer

  @vm_memory_interval :timer.seconds(5)

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    args
    |> Keyword.get(:vm_memory_interval, @vm_memory_interval)
    |> :timer.send_interval(:collect_vm_metrics)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:collect_vm_metrics, state) do
    measurements = Enum.into(:erlang.memory(), %{})
    total_run_queue = :erlang.statistics(:total_run_queue_lengths_all)
    cpu_run_queue = :erlang.statistics(:total_run_queue_lengths)
    io_run_queue = total_run_queue - cpu_run_queue

    reporter = Node.self()

    [
      %{
        metrics: [
          %{
            name: "vm.memory.total",
            value: measurements.total / 1_000,
            unit: " kilobyte",
            info: "",
            tags: %{},
            type: "summary"
          }
        ],
        reporter: reporter,
        measurements: measurements
      },
      %{
        metrics: [
          %{
            name: "vm.total_run_queue_lengths.total",
            value: total_run_queue,
            unit: "",
            info: "",
            tags: %{},
            type: "summary"
          }
        ],
        reporter: reporter,
        measurements: %{}
      },
      %{
        metrics: [
          %{
            name: "vm.total_run_queue_lengths.cpu",
            value: cpu_run_queue,
            unit: "",
            info: "",
            tags: %{},
            type: "summary"
          }
        ],
        reporter: reporter,
        measurements: %{}
      },
      %{
        metrics: [
          %{
            name: "vm.total_run_queue_lengths.io",
            value: io_run_queue,
            unit: "",
            info: "",
            tags: %{},
            type: "summary"
          }
        ],
        reporter: reporter,
        measurements: %{}
      }
    ]
    |> Enum.each(&ObserverWeb.Telemetry.push_data(&1))

    {:noreply, state}
  end
end
