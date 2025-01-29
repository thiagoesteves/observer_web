defmodule Observer.Web.Page do
  @moduledoc false

  alias Phoenix.LiveView.Socket

  @doc """
  Called from parent live view on mount and before page changes.
  """
  @callback handle_mount(socket :: Socket.t()) :: Socket.t()

  @doc """
  Called by parent live view on param changes.
  """
  @callback handle_params(params :: map(), uri :: String.t(), socket :: Socket.t()) ::
              {:noreply, Socket.t()}

  @doc """
  Called by parent live view on info messages.
  """
  @callback handle_info(message :: term(), socket :: Socket.t()) :: {:noreply, Socket.t()}

  @doc """
  Called by parent live view on handle_event messages.
  """
  @callback handle_parent_event(message :: term(), value :: term(), socket :: Socket.t()) ::
              {:noreply, Socket.t()}
end
