defmodule ObserverWeb.Telemetry.Producer.SchedulerWallTimeTest do
  use ExUnit.Case, async: false

  alias ObserverWeb.Telemetry.Producer.SchedulerWallTime

  test "emits [:vm, :scheduler] utilization events and manages the scheduler_wall_time flag" do
    handler_id = {__MODULE__, :utilization}
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:vm, :scheduler],
      fn [:vm, :scheduler], measurements, _metadata, _config ->
        send(test_pid, {:scheduler_event, measurements})
      end,
      nil
    )

    pid = start_supervised!({SchedulerWallTime, interval_ms: 50})

    # The flag is enabled for the lifetime of the producer (statistics returns :undefined when
    # the scheduler_wall_time flag is off, a list of per-scheduler tuples when on)
    assert is_list(:erlang.statistics(:scheduler_wall_time))

    assert_receive {:scheduler_event, %{utilization: utilization}}, 1_000
    assert is_float(utilization)
    assert utilization >= 0.0 and utilization <= 100.0

    # And switched back off when it terminates
    :ok = stop_supervised!(SchedulerWallTime)
    refute Process.alive?(pid)
    assert :erlang.statistics(:scheduler_wall_time) == :undefined
  after
    :telemetry.detach({__MODULE__, :utilization})
  end
end
