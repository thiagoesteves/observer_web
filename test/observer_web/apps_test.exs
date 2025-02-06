defmodule ObserverWeb.AppsTest do
  use ExUnit.Case, async: true

  import Mox

  alias ObserverWeb.Apps

  setup :verify_on_exit!

  test "list/0" do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    assert Enum.find(Apps.list(), &(&1.name == :kernel))
  end

  test "info/0" do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info()

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info(Node.self(), :observer_web)

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info(Node.self(), :phoenix_pubsub)

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info(Node.self(), :logger)
  end
end
