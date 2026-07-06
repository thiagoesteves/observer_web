defmodule ObserverWeb.Tracer.Tool.Collect do
  @moduledoc """
  Collects samples per key, for tools that aggregate values before reporting
  (e.g. the Duration tool's sum/avg/min/max/dist aggregation modes).

  Ported from https://github.com/gabiz/tracer's `Tracer.Collect`.
  """

  alias __MODULE__

  @type t :: %__MODULE__{collections: %{optional(term()) => list()}}

  defstruct collections: %{}

  @spec new :: t()
  def new, do: %Collect{}

  @spec add_sample(t(), term(), term()) :: t()
  def add_sample(%Collect{collections: collections} = state, key, value) do
    collection = [value | Map.get(collections, key, [])]
    %{state | collections: Map.put(collections, key, collection)}
  end

  @spec get_collections(t()) :: [{term(), list()}]
  def get_collections(%Collect{collections: collections}) do
    Enum.map(collections, fn {key, value} -> {key, Enum.reverse(value)} end)
  end
end
