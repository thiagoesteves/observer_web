defmodule Observer.Web.Components.Metrics.VmMemory do
  @moduledoc false
  use Observer.Web, :html

  use Phoenix.Component

  alias Observer.Web.Components.Metrics.Common
  alias Observer.Web.Helpers

  attr :title, :string, required: true
  attr :service, :string, required: true
  attr :metric, :string, required: true
  attr :metrics, :list, required: true
  attr :cols, :integer, default: 2

  def content(assigns) do
    ~H"""
    <div :if={@metric == "vm.memory.total"} style={"grid-column: span #{@cols};"}>
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

  defp normalize(metrics) do
    empty_series_data = %{
      atom: [],
      atom_used: [],
      binary: [],
      code: [],
      ets: [],
      processes: [],
      processes_used: [],
      system: [],
      total: []
    }

    # NOTE: Streams are retrieved in the reverse order
    {series_data, categories_data} =
      Enum.reduce(metrics, {empty_series_data, []}, fn
        %ObserverWeb.Telemetry.Data{value: nil} = metric, {series_data, categories_data} ->
          timestamp = Common.timestamp_to_string(metric.timestamp)

          {%{
             atom: [nil] ++ series_data.atom,
             atom_used: [nil] ++ series_data.atom_used,
             binary: [nil] ++ series_data.binary,
             code: [nil] ++ series_data.code,
             ets: [nil] ++ series_data.ets,
             processes: [nil] ++ series_data.processes,
             processes_used: [nil] ++ series_data.processes_used,
             system: [nil] ++ series_data.system,
             total: [nil] ++ series_data.total
           }, [timestamp] ++ categories_data}

        metric, {series_data, categories_data} ->
          timestamp = Common.timestamp_to_string(metric.timestamp)

          {%{
             atom: [metric.measurements.atom] ++ series_data.atom,
             atom_used: [metric.measurements.atom_used] ++ series_data.atom_used,
             binary: [metric.measurements.binary] ++ series_data.binary,
             code: [metric.measurements.code] ++ series_data.code,
             ets: [metric.measurements.ets] ++ series_data.ets,
             processes: [metric.measurements.processes] ++ series_data.processes,
             processes_used: [metric.measurements.processes_used] ++ series_data.processes_used,
             system: [metric.measurements.system] ++ series_data.system,
             total: [metric.measurements.total] ++ series_data.total
           }, [timestamp] ++ categories_data}
      end)

    datasets =
      [
        %{
          name: "Atom",
          type: "line",
          data: series_data.atom
        },
        %{
          name: "Atom Used",
          type: "line",
          data: series_data.atom_used
        },
        %{
          name: "Binary",
          type: "line",
          data: series_data.binary
        },
        %{
          name: "Code",
          type: "line",
          data: series_data.code
        },
        %{
          name: "Ets",
          type: "line",
          data: series_data.ets
        },
        %{
          name: "Processes",
          type: "line",
          data: series_data.processes
        },
        %{
          name: "Processes Used",
          type: "line",
          data: series_data.processes_used
        },
        %{
          name: "System",
          type: "line",
          data: series_data.system
        },
        %{
          name: "Total",
          type: "line",
          data: series_data.total
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
          "Atom",
          "Atom Used",
          "Binary",
          "Code",
          "Ets",
          "Processes",
          "Processes Used",
          "System",
          "Total"
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
