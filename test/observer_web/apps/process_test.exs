defmodule ObserverWeb.Apps.ProcessTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Apps.Process, as: AppsPort

  setup :verify_on_exit!

  test "info/1" do
    ObserverWeb.RpcMock
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    kernel_pid = :application_controller.get_master(:kernel)

    assert %{error_handler: :error_handler, memory: _, relations: %{links: [head, tail]}} =
             AppsPort.info(kernel_pid)

    assert %{error_handler: :error_handler, memory: _, relations: _} = AppsPort.info(head)
    assert %{error_handler: :error_handler, memory: _, relations: _} = AppsPort.info(tail)
    invalid_pid = "<0.11111.0>" |> String.to_charlist() |> :erlang.list_to_pid()
    assert :undefined = AppsPort.info(invalid_pid)
    process = Process.whereis(Elixir.ObserverWeb.Application)

    assert %{error_handler: :error_handler, memory: _, relations: _} =
             AppsPort.info(process)
  end
end
