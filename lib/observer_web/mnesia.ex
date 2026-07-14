defmodule ObserverWeb.Mnesia do
  @moduledoc """
  Lists a node's Mnesia tables and (optionally) previews their contents - the Mnesia side of the
  observer GUI's Table Viewer, sharing the Tables page (and its safety gating) with
  `ObserverWeb.Ets`.

  Table listing delegates to `:observer_backend.get_table_list` (runtime_tools, already
  required on every node for `:dbg` tracing). Nodes where Mnesia isn't running - or whose
  release doesn't ship the `:mnesia` application at all - report `{:error, :mnesia_not_running}`
  instead of crashing.

  ## Content inspection

  Bounded, read-only previews reuse the same opt-in as ETS tables
  (`config :observer_web, table_content_inspection: true`). Reads go straight to the table's
  storage layer: `ram_copies`/`disc_copies` tables are backed by an ETS table of the same name,
  `disc_only_copies` by a DETS table - both support bounded object fetches, so a preview never
  scans a whole table. Tables with no copy on the selected node report as not accessible.
  """

  alias ObserverWeb.Ets
  alias ObserverWeb.Rpc

  @rpc_timeout 10_000
  @content_preview_limit 50

  @type table :: %{
          name: atom(),
          storage: atom(),
          size: non_neg_integer(),
          type: atom(),
          memory: non_neg_integer(),
          owner_label: String.t(),
          index: list()
        }

  @doc """
  Lists every Mnesia table on `node` (including Mnesia's own system tables; the `schema` table
  is not listed by the collector).
  """
  @spec list_tables(node()) :: {:ok, [table()]} | {:error, :mnesia_not_running | term()}
  def list_tables(node) do
    case Rpc.call(
           node,
           :observer_backend,
           :get_table_list,
           [:mnesia, [sys_hidden: false]],
           @rpc_timeout
         ) do
      tables when is_list(tables) ->
        {:ok, tables |> Enum.map(&decode_table/1) |> Enum.reject(&is_nil/1)}

      # get_table_list throws {error, 'Mnesia is not running on: ...'} when the schema table
      # doesn't exist - which is also what a release without the :mnesia application reports.
      # :rpc.call propagates the thrown term as the return value.
      {:error, [_ | _] = _message} ->
        {:error, :mnesia_not_running}

      {:badrpc, reason} ->
        {:error, reason}

      unexpected ->
        {:error, {:unexpected_reply, unexpected}}
    end
  end

  defp decode_table(proplist) when is_list(proplist) do
    owner = Keyword.get(proplist, :owner)
    reg_name = Keyword.get(proplist, :reg_name)

    %{
      name: Keyword.get(proplist, :name),
      storage: Keyword.get(proplist, :storage, :unknown),
      size: Keyword.get(proplist, :size, 0),
      type: Keyword.get(proplist, :type),
      memory: Keyword.get(proplist, :memory, 0),
      owner_label: owner_label(owner, reg_name),
      index: Keyword.get(proplist, :index, [])
    }
  end

  # coveralls-ignore-start
  defp decode_table(_unexpected), do: nil
  # coveralls-ignore-stop

  defp owner_label(owner, reg_name) when reg_name in [nil, :ignore], do: inspect(owner)
  defp owner_label(_owner, reg_name), do: inspect(reg_name)

  @doc """
  Reads the first objects of a table straight from its storage layer (bounded, read-only),
  rendered as inspected strings. Same gating and limits as `ObserverWeb.Ets.table_content/2`.
  """
  @spec table_content(node(), atom()) ::
          {:ok, [String.t()]} | {:error, :content_inspection_disabled | :not_accessible}
  def table_content(node, table) do
    if Ets.content_inspection_enabled?() do
      fetch_content(node, table)
    else
      {:error, :content_inspection_disabled}
    end
  end

  defp fetch_content(node, table) do
    case Rpc.call(node, :mnesia, :table_info, [table, :storage_type], @rpc_timeout) do
      storage when storage in [:ram_copies, :disc_copies] ->
        ets_content(node, table)

      :disc_only_copies ->
        dets_content(node, table)

      # :unknown (no copy of the table on this node) or any rpc failure
      _no_local_copy ->
        {:error, :not_accessible}
    end
  end

  defp ets_content(node, table) do
    case Rpc.call(node, :ets, :match_object, [table, :_, @content_preview_limit], @rpc_timeout) do
      {objects, _continuation} when is_list(objects) -> {:ok, render_objects(objects)}
      :"$end_of_table" -> {:ok, []}
      _gone -> {:error, :not_accessible}
    end
  end

  defp dets_content(node, table) do
    case Rpc.call(node, :dets, :match_object, [table, :_, @content_preview_limit], @rpc_timeout) do
      {objects, _continuation} when is_list(objects) ->
        {:ok, render_objects(objects)}

      :"$end_of_table" ->
        {:ok, []}

      # coveralls-ignore-start
      _gone ->
        {:error, :not_accessible}
        # coveralls-ignore-stop
    end
  end

  defp render_objects(objects) do
    Enum.map(objects, &inspect(&1, limit: 50, printable_limit: 512))
  end
end
