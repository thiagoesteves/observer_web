defmodule ObserverWeb.Telemetry.Producer do
  @moduledoc """
  GenServer that collects the vm metrics and produce its statistics
  """
  use GenServer
  require Logger

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Logger.info("Initialising Telemetry Producer")

    :timer.send_interval(5_000, :collect_vm_metrics)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:collect_vm_metrics, state) do
    measurements = Enum.into(:erlang.memory(), %{})
    # IO.inspect Node.self
    # IO.inspect measurements

    node = Node.self()

    event = %{
      metrics: [
        %{
          name: "ow.vm.memory.total",
          version: "0.1.0-rc4",
          value: measurements.total / 1000,
          unit: " kilobyte",
          info: "",
          tags: %{},
          type: "summary"
        }
      ],
      reporter: node,
      measurements: measurements
    }

    ObserverWeb.Telemetry.push_data(event)
    {:noreply, state}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
