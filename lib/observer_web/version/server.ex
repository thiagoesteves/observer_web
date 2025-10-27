defmodule ObserverWeb.Version.Server do
  @moduledoc """
  Monitors and reports Observer Web versions across connected nodes.
  """

  use GenServer

  alias ObserverWeb.Rpc

  @wait_interval 60_000
  @rpc_timeout 1_000

  @type t :: %__MODULE__{
          status: :ok | :warning | :empty,
          local: String.t() | nil,
          nodes: tuple() | nil
        }

  defstruct status: :empty,
            local: nil,
            nodes: nil

  @table_name :observer_web_versions
  @key :state

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ets.new(@table_name, [:set, :protected, :named_table])

    state = %__MODULE__{}
    :ets.insert(@table_name, {@key, state})
    {:ok, state, {:continue, :check_versions}}
  end

  @impl true
  def handle_continue(:check_versions, _state) do
    state = update_versions()
    schedule_update()
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_versions, _state) do
    state = update_versions()
    schedule_update()
    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  @spec status :: __MODULE__.t()
  def status do
    [{_, value}] = :ets.lookup(@table_name, @key)
    value
  rescue
    _ ->
      %__MODULE__{}
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
  defp schedule_update,
    do: Process.send_after(self(), :check_versions, @wait_interval)

  defp update_versions do
    local = to_string(Application.spec(:observer_web, :vsn) || "")

    nodes =
      [Node.self() | Node.list()]
      |> Enum.reduce(%{}, fn node, acc ->
        case Rpc.call(node, Application, :spec, [:observer_web, :vsn], @rpc_timeout) do
          version when is_list(version) ->
            Map.put(acc, node, version |> to_string())

          _error ->
            acc
        end
      end)

    all_same? = Enum.all?(nodes, fn {_node, v} -> v == local end)

    state = %__MODULE__{
      status: if(all_same?, do: :ok, else: :warning),
      local: local,
      nodes: nodes
    }

    :ets.insert(@table_name, {@key, state})
    state
  end
end
