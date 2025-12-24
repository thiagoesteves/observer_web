defmodule Observer.Web.Components.Metrics.Common do
  @moduledoc false

  def timestamp_to_string(timestamp) do
    timestamp
    |> trunc()
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_string()
  end

  def data_from_streams(inserts) do
    Enum.map(inserts, fn
      {_id, _index, data, _} -> data
      {_id, _index, data, _, _} -> data
    end)
  end
end
