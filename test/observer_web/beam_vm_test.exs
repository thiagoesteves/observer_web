defmodule ObserverWeb.BeamVmTest do
  use ExUnit.Case, async: false

  import Mock

  alias ObserverWeb.Telemetry.Producer.BeamVm

  test "Check the Beam VM statistic info is being published" do
    with_mock :telemetry,
      execute: fn
        [:vm, :port],
        %{
          total: _,
          limit: _
        },
        %{} ->
          :ok

        [:vm, :atom],
        %{
          total: _,
          limit: _
        },
        %{} ->
          :ok

        [:vm, :process],
        %{
          total: _,
          limit: _
        },
        %{} ->
          :ok
      end,
      attach: fn _id, _event, _handler, _config ->
        :ok
      end do
      assert :ok == BeamVm.process()
    end
  end
end
