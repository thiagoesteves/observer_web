defmodule ObserverWeb.Telemetry.StorageTest do
  use ExUnit.Case, async: false

  alias ObserverWeb.Telemetry.Storage

  test "push_data/1 try to push data when mode is not configured" do
    assert :ok == Storage.push_data(%ObserverWeb.Telemetry.Data{})
  end
end
