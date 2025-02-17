defmodule ObserverWeb.VmDataTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Telemetry.Producer.VmData

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "Start Server and check the memory is published" do
    {:ok, _pid} = VmData.start_link(vm_memory_interval: 10)
    node = Node.self()
    test_pid_process = self()

    ObserverWeb.TelemetryMock
    |> expect(:push_data, fn event ->
      assert %{
               metrics: [
                 %{
                   name: "vm.memory.total",
                   value: _,
                   unit: " kilobyte",
                   info: "",
                   tags: %{},
                   type: "summary"
                 }
               ],
               reporter: ^node,
               measurements: %{
                 atom: _,
                 atom_used: _,
                 binary: _,
                 code: _,
                 ets: _,
                 processes: _,
                 processes_used: _,
                 system: _,
                 total: _
               }
             } = event

      send(test_pid_process, :received_data)
    end)

    assert_receive :received_data, 1_000
  end
end
