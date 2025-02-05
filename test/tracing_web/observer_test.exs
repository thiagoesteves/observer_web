defmodule ObserverWeb.ObserverTest do
  use ExUnit.Case, async: true

  import Mox

  alias ObserverWeb.Observer

  setup :verify_on_exit!

  test "list/0" do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    assert Enum.find(Observer.list(), &(&1.name == :kernel))
  end

  test "info/0" do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    assert %Observer{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Observer.info()

    assert %Observer{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Observer.info(Node.self(), :observer_web)

    assert %Observer{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Observer.info(Node.self(), :phoenix_pubsub)

    assert %Observer{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Observer.info(Node.self(), :logger)
  end
end
