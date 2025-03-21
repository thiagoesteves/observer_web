defmodule ObserverWeb.PhxLvSocket do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias ObserverWeb.Telemetry.Producer.PhxLvSocket

  setup :verify_on_exit!

  test "Check the phoenix liveview socket info is being published" do
    RpcStubber.defaults()

    with_mock :telemetry,
      execute: fn [:phoenix, :liveview, :socket, :"observer.web"],
                  %{
                    supervisors: _,
                    total: _,
                    connected: _
                  },
                  %{} ->
        :ok
      end,
      attach: fn _id, _event, _handler, _config ->
        :ok
      end do
      assert :ok == PhxLvSocket.process_phoenix_liveview_sockets()
    end
  end
end
