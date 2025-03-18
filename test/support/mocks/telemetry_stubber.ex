defmodule Observer.Web.Mocks.TelemetryStubber do
  @moduledoc false

  import Mox

  def defaults do
    ObserverWeb.TelemetryMock
    |> stub(:push_data, fn _event -> :ok end)
    |> stub(:list_active_nodes, fn -> [Node.self()] ++ Node.list() end)
    |> stub(:mode, fn -> :local end)
  end
end
