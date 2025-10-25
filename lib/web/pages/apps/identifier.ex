defmodule Observer.Web.Apps.Identifier do
  @moduledoc """
  This module provides Identifier Structure
  """

  # NOTE: Debouncing for reading the selected process
  @tooltip_debouncing 50

  @type t :: %__MODULE__{
          info: ObserverWeb.Apps.Process.t() | ObserverWeb.Apps.Port.t() | nil,
          id_string: String.t() | nil,
          type: nil,
          debouncing: non_neg_integer(),
          node: atom() | nil,
          metric: String.t() | nil,
          memory_monitor: boolean()
        }

  defstruct info: nil,
            id_string: nil,
            type: nil,
            debouncing: @tooltip_debouncing,
            node: nil,
            metric: nil,
            memory_monitor: false
end
