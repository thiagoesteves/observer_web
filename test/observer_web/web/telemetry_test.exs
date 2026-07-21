defmodule Observer.Web.TelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Telemetry.Metrics

  alias Observer.Web.Telemetry

  defmodule HostMetrics do
    import Elixir.Telemetry.Metrics, only: [summary: 2, counter: 1]

    def metrics do
      [
        summary("my_app.repo.query.total_time", unit: {:native, :millisecond}),
        counter("my_app.orders.created.count")
      ]
    end
  end

  setup do
    on_exit(fn -> Application.delete_env(:observer_web, :telemetry_metrics) end)
  end

  test "metrics/0 returns only the built-in metrics when nothing is configured" do
    metrics = Telemetry.metrics()

    assert summary("vm.memory.total", unit: {:byte, :kilobyte}) in metrics
    assert Telemetry.custom_metrics() == []
  end

  test "metrics/0 appends host metrics configured as a list" do
    custom = last_value("my_app.queue.length")

    Application.put_env(:observer_web, :telemetry_metrics, [custom])

    metrics = Telemetry.metrics()

    assert custom in metrics
    assert summary("vm.memory.total", unit: {:byte, :kilobyte}) in metrics
    assert Telemetry.custom_metrics() == [custom]
  end

  test "metrics/0 resolves host metrics configured as an MFA" do
    Application.put_env(:observer_web, :telemetry_metrics, {HostMetrics, :metrics, []})

    assert Telemetry.custom_metrics() == HostMetrics.metrics()
  end

  test "invalid entries are dropped with a warning" do
    custom = sum("my_app.bytes.total")

    Application.put_env(:observer_web, :telemetry_metrics, [custom, :not_a_metric])

    log =
      capture_log(fn ->
        assert Telemetry.custom_metrics() == [custom]
      end)

    assert log =~ "Ignoring invalid entry"
    assert log =~ ":not_a_metric"
  end

  test "an invalid config shape is ignored with a warning" do
    Application.put_env(:observer_web, :telemetry_metrics, "nope")

    log =
      capture_log(fn ->
        assert Telemetry.custom_metrics() == []
      end)

    assert log =~ "Ignoring :observer_web, :telemetry_metrics"
  end
end
