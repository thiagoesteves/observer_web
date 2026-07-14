defmodule Observer.Web.Apps.Identifier do
  @moduledoc """
  This module provides Identifier Structure
  """

  @type t :: %__MODULE__{
          info: ObserverWeb.Apps.Process.t() | ObserverWeb.Apps.Port.t() | nil,
          id_string: String.t() | nil,
          type: nil,
          fetched_at: integer() | nil,
          node: atom() | nil,
          metric: String.t() | nil,
          memory_monitor: boolean()
        }

  defstruct info: nil,
            id_string: nil,
            type: nil,
            fetched_at: nil,
            node: nil,
            metric: nil,
            memory_monitor: false
end
