defmodule ObserverWeb.PhxLvSocket do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  setup :verify_on_exit!

  alias ObserverWeb.Telemetry.Producer.PhxLvSocket

  test "Check the phoenix liveview socket info is being published" do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    with_mock :telemetry,
      execute: fn [:phoenix, :liveview, :socket],
                  %{
                    supervisors: _,
                    total: _,
                    connected: _
                  },
                  %{} ->
        :ok
      end do
      assert :ok == PhxLvSocket.process_phoenix_liveview_sockets()
    end
  end
end
