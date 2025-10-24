defmodule ObserverWeb.Apps.Port do
  @moduledoc """
  Retrieve Port information
  """

  alias ObserverWeb.Rpc

  @type t :: %{
          name: charlist() | String.t(),
          id: non_neg_integer(),
          connected: pid(),
          os_pid: non_neg_integer() | :undefined
        }

  defstruct [:name, :id, :connected, :os_pid]

  @doc """
  Return port information

  ## Examples

    iex> alias ObserverWeb.Observer.Port
    ...> [h | _] = :erlang.ports()
    ...> assert %{connected: _, id: _, name: _, os_pid: _} = Port.info(h)
    ...> assert :undefined = Port.info(nil)
    ...> assert :undefined = Port.info("")
  """
  @spec info(atom(), port()) :: :undefined | __MODULE__.t()
  def info(node \\ Node.self(), port)

  def info(node, port) when is_port(port) do
    case Rpc.call(node, :erlang, :port_info, [port], :infinity) do
      data when is_list(data) ->
        %__MODULE__{
          name: Keyword.get(data, :name, 0),
          id: Keyword.get(data, :id, 0),
          connected: Keyword.get(data, :connected, 0),
          os_pid: Keyword.get(data, :os_pid, 0)
        }

      _ ->
        :undefined
    end
  end

  def info(_node, _port), do: :undefined
end
