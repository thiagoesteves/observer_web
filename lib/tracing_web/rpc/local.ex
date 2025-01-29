defmodule TracingWeb.Rpc.Local do
  @moduledoc """
    Local Rpc implementation
  """

  @behaviour TracingWeb.Rpc.Adapter

  ### ==========================================================================
  ### Rpc Callbacks
  ### ==========================================================================
  @impl true
  def call(node, module, function, args, timeout) do
    :rpc.call(node, module, function, args, timeout)
  end
end
