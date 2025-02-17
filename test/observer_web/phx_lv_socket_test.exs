defmodule ObserverWeb.PhxLvSocket do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Telemetry.Producer.PhxLvSocket

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  test "Start Server and check the memory is published" do
    {:ok, _pid} = PhxLvSocket.start_link(phoenix_interval: 50)
    node = Node.self()
    test_pid_process = self()

    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    ObserverWeb.TelemetryMock
    |> expect(:push_data, fn event ->
      assert %{
               metrics: [
                 %{
                   name: "phoenix.liveview.socket.total",
                   value: _,
                   unit: "",
                   info: "",
                   tags: %{},
                   type: "summary"
                 }
               ],
               reporter: ^node,
               measurements: %{
                 supervisors_total: _,
                 sockets_total: _,
                 sockets_connected: _
               }
             } = event

      send(test_pid_process, :received_data)
    end)

    assert_receive :received_data, 1_000
  end
end
