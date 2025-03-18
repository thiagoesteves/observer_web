defmodule ObserverWeb.Apps.PortTest do
  use ExUnit.Case, async: true

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias ObserverWeb.Apps.Port, as: AppsPort

  setup :verify_on_exit!

  test "info/2" do
    RpcStubber.defaults()

    invalid_port =
      "#Port<0.1000>"
      |> String.to_charlist()
      |> :erlang.list_to_port()

    [h | _] = :erlang.ports()
    assert %{connected: _, id: _, name: _, os_pid: _} = AppsPort.info(h)
    assert %{connected: _, id: _, name: _, os_pid: _} = AppsPort.info(Node.self(), h)
    assert :undefined = AppsPort.info(Node.self(), invalid_port)
    assert :undefined = AppsPort.info(Node.self(), nil)
  end
end
