defmodule ObserverWeb.Telemetry.Consumer do
  @moduledoc """
   A reporter that sends the events and metrics to Observer Web consumer

   References:
     * https://github.com/beam-telemetry/telemetry_metrics/blob/main/lib/telemetry_metrics/console_reporter.ex
  """

  use GenServer
  require Logger

  alias Telemetry.Metrics

  @type option ::
          {:name, String.t()}
          | {:device, atom()}
          | {:metrics, [Metrics.t()]}
  @type options :: [option]

  @type t :: %__MODULE__{
          name: String.t(),
          value: integer() | float(),
          unit: String.t(),
          info: String.t(),
          tags: list(),
          type: String.t()
        }

  defstruct name: "unknown",
            value: "",
            unit: "",
            info: "",
            tags: [],
            type: ""

  @doc """
  Reporter's child spec.

  This function allows you to start the reporter under a supervisor like this:

      children = [
        {ObserverWeb.Telemetry.Consumer, options}
      ]

  See `start_link/1` for a list of available options.
  """
  @spec child_spec(options) :: Supervisor.child_spec()
  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}}
  end

  @spec start_link(options) :: GenServer.on_start()
  def start_link(options) do
    server_opts = Keyword.take(options, [:name])
    device = options[:device] || :stdio

    metrics =
      options[:metrics] ||
        raise ArgumentError, "the :metrics option is required by #{inspect(__MODULE__)}"

    GenServer.start_link(__MODULE__, {metrics, device}, server_opts)
  end

  @impl true
  def init({metrics, device}) do
    Process.flag(:trap_exit, true)
    groups = Enum.group_by(metrics, & &1.event_name)

    reporter = Node.self()

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}

      :telemetry.attach(
        id,
        event,
        &__MODULE__.handle_event/4,
        {metrics, device, reporter}
      )
    end

    {:ok, Map.keys(groups)}
  end

  @impl true
  def terminate(_, events) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end

  @doc false
  def handle_event(
        _event_name,
        measurements,
        metadata,
        {metrics, _device, reporter}
      ) do
    metrics =
      Enum.reduce(metrics, [], fn %struct{} = metric, acc ->
        data = %__MODULE__{name: "#{Enum.join(metric.name, ".")}", type: metric(struct)}
        measurement = extract_measurement(metric, measurements, metadata)

        tags =
          extract_tags(metric, metadata)
          |> add_phoenix_tags(metadata)

        cond do
          is_nil(measurement) ->
            acc

          not keep?(metric, metadata) ->
            acc

          metric.__struct__ == Telemetry.Metrics.Counter ->
            [%{data | tags: tags} | acc]

          true ->
            [
              %{
                data
                | value: measurement,
                  unit: unit(metric.unit),
                  info: info(measurement),
                  tags: tags
              }
              | acc
            ]
        end
      end)

    %{
      metrics: metrics,
      measurements: measurements,
      reporter: reporter
    }
    |> ObserverWeb.Telemetry.push_data()
  rescue
    e ->
      Logger.error([
        "Could not format metrics #{inspect(metrics)}\n",
        Exception.format(:error, e, __STACKTRACE__)
      ])
  end

  defp keep?(%{keep: nil}, _metadata), do: true
  defp keep?(metric, metadata), do: metric.keep.(metadata)

  defp extract_measurement(metric, measurements, metadata) do
    case metric.measurement do
      fun when is_function(fun, 2) -> fun.(measurements, metadata)
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end

  defp info(int) when is_number(int), do: ""
  defp info(_), do: " (WARNING! measurement should be a number)"

  defp unit(:unit), do: ""
  defp unit(unit), do: " #{unit}"

  defp metric(Telemetry.Metrics.Counter), do: "counter"
  defp metric(Telemetry.Metrics.Distribution), do: "distribution"
  defp metric(Telemetry.Metrics.LastValue), do: "last_value"
  defp metric(Telemetry.Metrics.Sum), do: "sum"
  defp metric(Telemetry.Metrics.Summary), do: "summary"

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end

  defp add_phoenix_tags(tags, %{conn: %{method: method, status: status}}) do
    tags
    |> Map.put(:method, method)
    |> Map.put(:status, status)
  end

  defp add_phoenix_tags(tags, _metadata), do: tags
end
