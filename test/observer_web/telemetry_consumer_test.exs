defmodule ObserverWeb.TelemetryConsumerTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics
  import ExUnit.CaptureLog

  import Mock

  alias ObserverWeb.Telemetry.Consumer

  def metadata_measurement(_measurements, metadata) do
    map_size(metadata)
  end

  def measurement(%{duration: duration} = _measurement) do
    duration
  end

  setup do
    metrics = [
      last_value("vm.memory.binary", unit: :byte),
      counter("vm.memory.total"),
      summary("http.request.response_time",
        tag_values: fn
          %{foo: :bar} -> %{bar: :baz}
        end,
        tags: [:bar],
        drop: fn metadata ->
          metadata[:boom] == :pow
        end
      ),
      sum("telemetry.event_size.metadata",
        measurement: &__MODULE__.metadata_measurement/2
      ),
      distribution("phoenix.endpoint.stop.duration",
        measurement: &__MODULE__.measurement/1
      ),
      summary("my_app.repo.query.query_time", unit: {:native, :millisecond})
    ]

    reporter = Node.self()
    opts = [metrics: metrics]
    {:ok, formatter} = Consumer.start_link(opts)
    {:ok, formatter: formatter, reporter: reporter}
  end

  test "can be a named process" do
    {:ok, pid} = Consumer.start_link(metrics: [], name: __MODULE__)
    assert Process.whereis(__MODULE__) == pid
  end

  test "raises when missing :metrics option" do
    msg = "the :metrics option is required by ObserverWeb.Telemetry.Consumer"

    assert_raise ArgumentError, msg, fn ->
      Consumer.start_link(name: __MODULE__)
    end
  end

  test "prints metrics per event", %{reporter: reporter} do
    test_pid_process = self()

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute([:vm, :memory], %{binary: 100, total: 200}, %{})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "vm.memory.total",
                   value: 0.2,
                   unit: " kilobyte",
                   info: "",
                   tags: %{},
                   type: "summary"
                 }
               ],
               measurements: %{binary: 100, total: 200},
               reporter: ^reporter
             } = event

      assert_receive {:capture_event, 1, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "vm.memory.total",
                   value: "",
                   unit: "",
                   info: "",
                   tags: %{},
                   type: "counter"
                 },
                 %Consumer{
                   name: "vm.memory.binary",
                   value: 100,
                   unit: " byte",
                   info: "",
                   tags: %{},
                   type: "last_value"
                 }
               ],
               measurements: %{binary: 100, total: 200},
               reporter: ^reporter
             } = event
    end
  end

  test "Allow nil values", %{reporter: reporter} do
    test_pid_process = self()

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute([:vm, :memory], %{binary: nil, total: 2000}, %{foo: :bar})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "vm.memory.total",
                   value: 2.0,
                   unit: " kilobyte",
                   info: "",
                   tags: %{},
                   type: "summary"
                 }
               ],
               measurements: %{binary: nil, total: 2000},
               reporter: ^reporter
             } = event

      assert_receive {:capture_event, 1, event}, 1_000

      assert %{
               metrics: [
                 _any,
                 %Consumer{
                   name: "vm.memory.binary",
                   value: nil,
                   unit: " byte",
                   info: " (WARNING! measurement should be a number)",
                   tags: %{},
                   type: "last_value"
                 }
               ],
               measurements: %{binary: nil, total: 2000},
               reporter: ^reporter
             } = event
    end
  end

  test "prints tag values measurements", %{reporter: reporter} do
    test_pid_process = self()

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute([:http, :request], %{response_time: 1000}, %{foo: :bar})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "http.request.response_time",
                   value: 1000,
                   unit: "",
                   info: "",
                   tags: %{bar: :baz},
                   type: "summary"
                 }
               ],
               measurements: %{response_time: 1000},
               reporter: ^reporter
             } = event
    end
  end

  test "filters events", %{reporter: reporter} do
    test_pid_process = self()

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute([:http, :request], %{response_time: 1000}, %{foo: :bar, boom: :pow})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [],
               measurements: %{response_time: 1000},
               reporter: ^reporter
             } = event
    end
  end

  test "logs bad metrics" do
    log =
      capture_log(fn ->
        :telemetry.execute([:http, :request], %{response_time: 1000}, %{bar: :baz})
      end)

    assert log =~ "Could not format metrics [%Telemetry.Metrics.Summary"
    assert log =~ "** (FunctionClauseError) no function clause matching"
  end

  test "can use metadata in the event measurement calculation", %{reporter: reporter} do
    test_pid_process = self()

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute([:telemetry, :event_size], %{}, %{key: :value})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "telemetry.event_size.metadata",
                   value: 1,
                   unit: "",
                   info: "",
                   tags: %{},
                   type: "sum"
                 }
               ],
               measurements: %{},
               reporter: ^reporter
             } = event
    end
  end

  @tag :capture_log
  test "can use measurement map in the event measurement calculation", %{reporter: reporter} do
    test_pid_process = self()

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute([:phoenix, :endpoint, :stop], %{duration: 100}, %{})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "phoenix.endpoint.stop.duration",
                   value: 9.999999999999999e-5,
                   unit: " millisecond",
                   info: "",
                   tags: %{},
                   type: "summary"
                 }
               ],
               measurements: %{duration: 100},
               reporter: ^reporter
             } = event

      assert_receive {:capture_event, 1, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "phoenix.endpoint.stop.duration",
                   value: 100,
                   unit: "",
                   info: "",
                   tags: %{},
                   type: "distribution"
                 }
               ],
               measurements: %{duration: 100},
               reporter: ^reporter
             } = event
    end
  end

  test "can show metric name and unit conversion fun", %{reporter: reporter} do
    test_pid_process = self()
    event = [:my_app, :repo, :query]
    native_time = :erlang.system_time()

    expected_millisecond = native_time * (1 / System.convert_time_unit(1, :millisecond, :native))

    with_mock ObserverWeb.Telemetry,
      push_data: fn event ->
        called = Process.get("event", 0)
        Process.put("event", called + 1)

        send(test_pid_process, {:capture_event, called, event})
        :ok
      end do
      :telemetry.execute(event, %{query_time: native_time})

      assert_receive {:capture_event, 0, event}, 1_000

      assert %{
               metrics: [
                 %Consumer{
                   name: "my_app.repo.query.query_time",
                   value: ^expected_millisecond,
                   unit: " millisecond",
                   info: "",
                   tags: %{},
                   type: "summary"
                 }
               ],
               measurements: %{query_time: ^native_time},
               reporter: ^reporter
             } = event
    end
  end
end
