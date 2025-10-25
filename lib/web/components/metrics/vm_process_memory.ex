defmodule Observer.Web.Components.Metrics.VmProcessMemory do
  @moduledoc false
  use Observer.Web, :html

  alias Observer.Web.Components.Metrics.Common
  alias Observer.Web.Helpers

  attr :title, :string, required: true
  attr :service, :string, required: true
  attr :metric, :string, required: true
  attr :metrics, :list, required: true
  attr :cols, :integer, default: 2

  def content(assigns) do
    ~H"""
    <div :if={String.match?(@metric, process_regex())} style={"grid-column: span #{@cols};"}>
      <% id = Helpers.normalize_id("#{@service}-#{@metric}") %>
      <div class="relative flex flex-col min-w-0 break-words bg-white w-full shadow-lg rounded border border-blueGray-100 dark:border-neutral-400">
        <div class="rounded-t mb-0 px-4 py-3 border-b">
          <div class="flex flex-wrap items-center">
            <div class="relative w-full px-4 max-w-full flex-grow flex-1">
              <h3 class="font-semibold text-base text-blueGray-700 dark:text-neutral-600">
                {@title}
              </h3>
            </div>
          </div>
        </div>

        <% metrics = Enum.map(@metrics.inserts, fn {_id, _index, data, _} -> data end) %>
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

  defp process_regex, do: ~r/^vm\.process\.memory\..+\.total$/

  # NOTE: Streams are retrieved in the reverse order
  defp normalize(metrics) do
    empty_series_data = %{
      total: [],
      stack_and_heap: [],
      heap_size: [],
      stack_size: [],
      gc_min_heap_size: [],
      gc_full_sweep_after: []
    }

    {series_data, categories_data} =
      Enum.reduce(metrics, {empty_series_data, []}, fn
        %ObserverWeb.Telemetry.Data{value: nil} = metric, {series_data, categories_data} ->
          timestamp = Common.timestamp_to_string(metric.timestamp)

          {%{
             total: [nil] ++ series_data.total,
             stack_and_heap: [nil] ++ series_data.stack_and_heap,
             stack_size: [nil] ++ series_data.stack_size,
             heap_size: [nil] ++ series_data.heap_size,
             gc_min_heap_size: [nil] ++ series_data.gc_min_heap_size,
             gc_full_sweep_after: [nil] ++ series_data.gc_full_sweep_after
           }, [timestamp] ++ categories_data}

        metric, {series_data, categories_data} ->
          timestamp = Common.timestamp_to_string(metric.timestamp)

          {%{
             total: [metric.measurements.total] ++ series_data.total,
             stack_and_heap: [metric.measurements.stack_and_heap] ++ series_data.stack_and_heap,
             stack_size: [metric.measurements.stack_size] ++ series_data.stack_size,
             heap_size: [metric.measurements.heap_size] ++ series_data.heap_size,
             gc_min_heap_size:
               [metric.measurements.gc_min_heap_size] ++ series_data.gc_min_heap_size,
             gc_full_sweep_after:
               [metric.measurements.gc_full_sweep_after] ++ series_data.gc_full_sweep_after
           }, [timestamp] ++ categories_data}
      end)

    datasets =
      [
        %{
          name: "Total",
          type: "line",
          data: series_data.total
        },
        %{
          name: "Stack+Heap",
          type: "line",
          data: series_data.stack_and_heap
        },
        %{
          name: "Stack",
          type: "line",
          data: series_data.stack_size
        },
        %{
          name: "Heap",
          type: "line",
          data: series_data.heap_size
        },
        %{
          name: "GC min heap",
          type: "line",
          data: series_data.gc_min_heap_size
        },
        %{
          name: "GC full sweep",
          type: "line",
          data: series_data.gc_full_sweep_after
        }
      ]

    %{
      datasets: datasets,
      categories: categories_data
    }
  end

  defp config(%{datasets: datasets, categories: categories}) do
    %{
      tooltip: %{
        trigger: "axis"
      },
      legend: %{
        data: [
          "Total",
          "Stack+Heap",
          "Stack",
          "Heap",
          "GC min heap",
          "GC full sweep"
        ],
        right: "25%"
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
          formatter: "{value} bytes"
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
