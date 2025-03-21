defmodule Observer.Web.Components.Metrics.Common do
  @moduledoc false

  def timestamp_to_string(timestamp) do
    timestamp
    |> trunc()
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_string()
  end
end
