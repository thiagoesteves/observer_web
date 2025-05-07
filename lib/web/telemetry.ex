defmodule Observer.Web.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  import ObserverWeb.Macros

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    # Telemetry poller will execute the given period measurements
    # every 5_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
    children =
      add_telemetry_poller() ++
        [
          # Add reporters as children of your supervision tree.
          {ObserverWeb.Telemetry.Consumer, metrics: metrics()}
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  if_not_test do
    alias ObserverWeb.Telemetry.Producer.BeamVm
    alias ObserverWeb.Telemetry.Producer.PhxLvSocket

    defp add_telemetry_poller,
      do: [
        {:telemetry_poller,
         name: :observer_web_phoenix_liveview_sockets,
         measurements: [{PhxLvSocket, :process, []}],
         period:
           Application.get_env(:observer_web, ObserverWeb.Telemetry)[
             :phx_lv_sckt_poller_interval_ms
           ] || 5_000},
        {:telemetry_poller,
         name: :observer_web_beam_vm,
         measurements: [{BeamVm, :process, []}],
         period:
           Application.get_env(:observer_web, ObserverWeb.Telemetry)[:beam_vm_poller_interval_ms] ||
             1_000}
      ]
  else
    defp add_telemetry_poller, do: []
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),
      summary("vm.port.total"),
      summary("vm.atom.total"),
      summary("vm.process.total")
    ]
  end
end
