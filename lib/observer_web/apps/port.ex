defmodule ObserverWeb.Apps.Port do
  @moduledoc """
  Retrieve Port information
  """

  alias ObserverWeb.Rpc

  @type t :: %{
          name: charlist() | String.t(),
          id: non_neg_integer(),
          connected: pid(),
          os_pid: non_neg_integer() | :undefined,
          memory: non_neg_integer()
        }

  defstruct [:name, :id, :connected, :os_pid, :memory]

  @doc """
  Return port information

  ## Examples

    iex> alias ObserverWeb.Observer.Port
    ...> [h | _] = :erlang.ports()
    ...> assert %{connected: _, id: _, name: _, os_pid: _, memory: _} = Port.info(h)
    ...> assert :undefined = Port.info(nil)
    ...> assert :undefined = Port.info("")
  """
  @spec info(node :: atom(), port :: port()) :: :undefined | ObserverWeb.Apps.Port.t()
  def info(node \\ Node.self(), port)

  def info(node, port) when is_port(port) do
    with data <- Rpc.call(node, :erlang, :port_info, [port], :infinity),
         true <- is_list(data),
         {:memory, memory} <- Rpc.call(node, :erlang, :port_info, [port, :memory], :infinity) do
      %__MODULE__{
        name: Keyword.get(data, :name, 0),
        id: Keyword.get(data, :id, 0),
        connected: Keyword.get(data, :connected, 0),
        os_pid: Keyword.get(data, :os_pid, 0),
        memory: memory
      }
    else
      _ ->
        :undefined
    end
  end

  def info(_node, _port), do: :undefined
end
