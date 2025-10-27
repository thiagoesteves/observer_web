defmodule ObserverWeb.Version do
  @moduledoc """
  This module contains the version context
  """

  alias ObserverWeb.Version.Server

  ### ==========================================================================
  ### Public API
  ### ==========================================================================
  @spec status :: Server.t()
  def status, do: Server.status()
end
