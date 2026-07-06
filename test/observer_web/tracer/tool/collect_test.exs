defmodule ObserverWeb.Tracer.Tool.CollectTest do
  use ExUnit.Case, async: true

  alias ObserverWeb.Tracer.Tool.Collect

  test "new/0 starts empty" do
    assert Collect.new() == %Collect{collections: %{}}
  end

  test "add_sample/3 accumulates samples per key in insertion order" do
    state =
      Collect.new()
      |> Collect.add_sample(:a, 1)
      |> Collect.add_sample(:a, 2)
      |> Collect.add_sample(:b, 3)

    assert Enum.sort(Collect.get_collections(state)) == [a: [1, 2], b: [3]]
  end
end
