defmodule Observer.Web.Mocks.RpcStubber do
  @moduledoc false

  import Mox

  def defaults do
    ObserverWeb.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)
  end
end
