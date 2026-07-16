defmodule Observer.Web.Telemetry do
  @moduledoc """
  Supervises the telemetry pollers and the reporter that feeds the Metrics page.

  ## Host application metrics

  Beyond the built-in VM and Phoenix series, any `Telemetry.Metrics` definition from the host
  application can be charted by configuring `:telemetry_metrics`:

  ```elixir
  config :observer_web,
    telemetry_metrics: [
      Telemetry.Metrics.summary("my_app.repo.query.total_time", unit: {:native, :millisecond}),
      Telemetry.Metrics.last_value("my_app.orders.queue.length")
    ]
  ```

  When the definitions are only available at runtime (or you want to share the same list used
  by `telemetry_metrics` reporters), point to a function instead:

  ```elixir
  config :observer_web, telemetry_metrics: {MyAppWeb.Telemetry, :metrics, []}
  ```

  The metrics are attached when the `:observer_web` application starts, and each series shows
  up on the Metrics page under its metric name once events are emitted. Entries that are not
  `Telemetry.Metrics` structs are ignored with a warning.
  """

  use Supervisor

  import Telemetry.Metrics
  import ObserverWeb.Macros

  require Logger

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
    alias ObserverWeb.Telemetry.Producer.SchedulerWallTime

    defp add_telemetry_poller,
      do:
        [
          {:telemetry_poller,
           name: :observer_web_phoenix_liveview_sockets,
           measurements: [{PhxLvSocket, :process, []}],
           period: Application.get_env(:observer_web, :phx_lv_sckt_poller_interval_ms) || 5_000},
          {:telemetry_poller,
           name: :observer_web_beam_vm,
           measurements: [{BeamVm, :process, []}],
           period: Application.get_env(:observer_web, :beam_vm_poller_interval_ms) || 1_000}
        ] ++ scheduler_utilization_producer()

    # Opt-in: scheduler wall time accounting adds a small permanent cost to every scheduler
    # (see ObserverWeb.Telemetry.Producer.SchedulerWallTime), so the utilization series is only
    # produced when an interval is configured.
    defp scheduler_utilization_producer do
      case Application.get_env(:observer_web, :scheduler_utilization_poller_interval_ms) do
        interval_ms when is_integer(interval_ms) and interval_ms > 0 ->
          [{SchedulerWallTime, interval_ms: interval_ms}]

        _disabled ->
          []
      end
    end
  else
    defp add_telemetry_poller, do: []
  end

  def metrics do
    default_metrics() ++ custom_metrics()
  end

  @doc """
  Host application metrics configured under `config :observer_web, :telemetry_metrics` -
  either a list of `Telemetry.Metrics` structs or a `{module, function, args}` returning one.
  """
  def custom_metrics do
    :observer_web
    |> Application.get_env(:telemetry_metrics, [])
    |> resolve_custom_metrics()
    |> Enum.filter(&valid_metric?/1)
  end

  defp resolve_custom_metrics({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    module |> apply(function, args) |> List.wrap()
  end

  defp resolve_custom_metrics(metrics) when is_list(metrics), do: metrics

  defp resolve_custom_metrics(invalid) do
    Logger.warning(
      "Ignoring :observer_web, :telemetry_metrics - expected a list of Telemetry.Metrics " <>
        "or a {module, function, args} tuple, got: #{inspect(invalid)}"
    )

    []
  end

  @metric_types [
    Telemetry.Metrics.Counter,
    Telemetry.Metrics.Distribution,
    Telemetry.Metrics.LastValue,
    Telemetry.Metrics.Sum,
    Telemetry.Metrics.Summary
  ]

  defp valid_metric?(%struct{}) when struct in @metric_types, do: true

  defp valid_metric?(invalid) do
    Logger.warning(
      "Ignoring invalid entry in :observer_web, :telemetry_metrics - expected a " <>
        "Telemetry.Metrics struct, got: #{inspect(invalid)}"
    )

    false
  end

  defp default_metrics do
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
      summary("vm.process.total"),
      summary("vm.scheduler.utilization", unit: :percent)
    ]
  end
end
