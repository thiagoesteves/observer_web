defmodule ObserverWeb.Telemetry.VmMemory do
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
  def init(_args) do
    :timer.send_interval(@vm_memory_interval, :collect_vm_metrics)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:collect_vm_metrics, state) do
    measurements = Enum.into(:erlang.memory(), %{})

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
      reporter: Node.self(),
      measurements: measurements
    }
    |> ObserverWeb.Telemetry.push_data()

    {:noreply, state}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
