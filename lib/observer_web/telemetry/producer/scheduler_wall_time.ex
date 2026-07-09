defmodule ObserverWeb.Telemetry.Producer.SchedulerWallTime do
  @moduledoc """
  Periodically reports the node's scheduler utilization as a `[:vm, :scheduler]` telemetry event
  (measurement `:utilization`, percent 0-100), computed from consecutive `:scheduler.sample/0`
  snapshots - the same `scheduler_wall_time` accounting `observer`'s load charts use.

  Unlike the other producers this one is stateful (utilization is the delta between two
  snapshots), so it runs as its own GenServer instead of a `:telemetry_poller` measurement.

  IMPORTANT: scheduler wall time accounting adds a small permanent cost to every scheduler, so
  this producer is opt-in - it only starts when
  `config :observer_web, :scheduler_utilization_poller_interval_ms` is set (see
  `Observer.Web.Telemetry`). The `:scheduler_wall_time` system flag is enabled for the lifetime
  of the producer and switched back off when it terminates.
  """

  use GenServer

  @default_interval_ms 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

    :erlang.system_flag(:scheduler_wall_time, true)

    schedule_tick(interval_ms)

    {:ok, %{interval_ms: interval_ms, sample: :scheduler.sample()}}
  end

  @impl true
  def handle_info(:tick, %{interval_ms: interval_ms, sample: previous_sample} = state) do
    sample = :scheduler.sample()

    case List.keyfind(:scheduler.utilization(previous_sample, sample), :total, 0) do
      {:total, fraction, _formatted} ->
        :telemetry.execute([:vm, :scheduler], %{utilization: fraction * 100}, %{})

      # coveralls-ignore-start
      nil ->
        :ok
        # coveralls-ignore-stop
    end

    schedule_tick(interval_ms)

    {:noreply, %{state | sample: sample}}
  end

  @impl true
  def terminate(_reason, _state) do
    :erlang.system_flag(:scheduler_wall_time, false)
  end

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end
end
