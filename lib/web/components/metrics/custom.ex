defmodule Observer.Web.Components.Metrics.Custom do
  @moduledoc false
  use Observer.Web, :html

  use Phoenix.Component

  alias Observer.Web.Components.Metrics.Common
  alias Observer.Web.Helpers

  # Every metric name (or pattern) already claimed by a dedicated chart component. A metric that
  # matches none of these - typically a host application metric configured via
  # `config :observer_web, telemetry_metrics: ...` - is rendered by this generic line chart.
  # Keep this in sync with the `supported_metrics`/regex gates of the sibling components.
  @builtin_metrics [
    # VmMemory
    "vm.memory.total",
    # VmRunQueue
    "vm.total_run_queue_lengths.total",
    "vm.total_run_queue_lengths.cpu",
    "vm.total_run_queue_lengths.io",
    # VmLimits
    "vm.atom.total",
    "vm.process.total",
    "vm.port.total",
    # VmSchedulerUtilization
    "vm.scheduler.utilization",
    # Phoenix
    "phoenix.endpoint.start.system_time",
    "phoenix.endpoint.stop.duration",
    "phoenix.router_dispatch.start.system_time",
    "phoenix.router_dispatch.exception.duration",
    "phoenix.router_dispatch.stop.duration",
    "phoenix.socket_connected.duration",
    "phoenix.channel_joined.duration",
    "phoenix.channel_handled_in.duration"
  ]

  @builtin_patterns [
    # PhxLvSocket
    ~r/^phoenix\.liveview\.socket\..+\.total$/,
    # VmProcessMemory
    ~r/^vm\.process\.memory\..+\.total$/,
    # VmPortMemory
    ~r/^vm\.port\.memory\..+\.total$/
  ]

  @doc """
  Whether this component is responsible for rendering `metric`: true for any metric no
  dedicated chart component claims.
  """
  def renders?(metric) do
    metric not in @builtin_metrics and
      not Enum.any?(@builtin_patterns, &String.match?(metric, &1))
  end

  attr :title, :string, required: true
  attr :service, :string, required: true
  attr :metric, :string, required: true
  attr :metrics, :list, required: true
  attr :cols, :integer, default: 2

  def content(assigns) do
    ~H"""
    <div :if={renders?(@metric)} style={"grid-column: span #{@cols};"}>
      <% id = Helpers.normalize_id("#{@service}-#{@metric}") %>
      <div class="relative flex flex-col min-w-0 break-words bg-white w-full shadow-lg rounded border border-blueGray-100 dark:border-neutral-600">
        <div class="rounded-t mb-0 px-4 py-3 border-b">
          <div class="flex flex-wrap items-center">
            <div class="relative w-full px-4 max-w-full flex-grow flex-1">
              <h3 class="font-semibold text-base text-blueGray-700 dark:text-neutral-600">
                {@title}
              </h3>
            </div>
          </div>
        </div>

        <% metrics = Common.data_from_streams(@metrics.inserts) %>
        <% normalized_metrics = normalize(metrics) %>
        <% echart_config = config(normalized_metrics) %>

        <div
          id={id}
          phx-hook="LiveMetricsEChart"
          data-config={Jason.encode!(echart_config)}
          data-reset={Jason.encode!(@metrics.reset?)}
          data-columns={Jason.encode!(@cols)}
          phx-update="ignore"
        >
          <div id={"#{id}-chart"} class="h-64" />
        </div>
      </div>
    </div>
    """
  end

  # NOTE: Streams are retrieved in the reverse order
  defp normalize(metrics) do
    {series_data, categories_data, unit} =
      Enum.reduce(metrics, {[], [], nil}, fn
        %ObserverWeb.Telemetry.Data{value: nil} = metric, {series_data, categories_data, unit} ->
          timestamp = Common.timestamp_to_string(metric.timestamp)

          {[nil] ++ series_data, [timestamp] ++ categories_data, unit}

        metric, {series_data, categories_data, unit} ->
          timestamp = Common.timestamp_to_string(metric.timestamp)

          {[metric.value] ++ series_data, [timestamp] ++ categories_data,
           unit || present_unit(metric.unit)}
      end)

    datasets =
      [
        %{
          name: unit || "Value",
          type: "line",
          data: series_data
        }
      ]

    %{
      datasets: datasets,
      categories: categories_data
    }
  end

  defp present_unit(unit) when unit in [nil, ""], do: nil
  defp present_unit(unit), do: unit |> to_string() |> String.trim()

  defp config(%{datasets: datasets, categories: categories}) do
    %{
      tooltip: %{
        trigger: "axis"
      },
      grid: %{
        left: "3%",
        right: "4%",
        bottom: "3%",
        top: "30%",
        containLabel: true
      },
      toolbox: %{
        feature: %{
          dataZoom: %{},
          dataView: %{},
          saveAsImage: %{}
        }
      },
      yAxis: %{
        type: "value",
        axisLabel: %{
          formatter: "{value}"
        }
      },
      series: datasets,
      xAxis: %{
        type: "category",
        boundaryGap: false,
        data: categories
      }
    }
  end
end
