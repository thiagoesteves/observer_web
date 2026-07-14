defmodule ObserverWeb.Ets do
  @moduledoc """
  Lists a node's ETS tables and (optionally) previews their contents - the web equivalent of the
  observer GUI's Table Viewer and observer_cli's Ets pane.

  Table listing delegates to `:observer_backend.get_table_list` (runtime_tools, already
  required on every node for `:dbg` tracing): one RPC round trip returns every table's metadata,
  regardless of the observer_web version on the observed node.

  ## Content inspection

  Table contents are live production data, so previewing them is **disabled by default** and
  gated behind an explicit opt-in:

      config :observer_web, table_content_inspection: true

  Even when enabled, previews are read-only and bounded: at most 50 objects per request,
  each rendered with `inspect` limits. Note that the objects are copied from the observed node
  before truncation - previewing a table whose single objects are huge moves that data over the
  distribution. Private tables can never be read from another process; their metadata still
  shows, and the preview reports them as not accessible.
  """

  alias ObserverWeb.Rpc

  @rpc_timeout 10_000
  @content_preview_limit 50

  @type table :: %{
          name: atom(),
          handle: atom() | reference(),
          protection: :public | :protected | :private,
          owner: pid(),
          owner_label: String.t(),
          size: non_neg_integer(),
          type: atom(),
          memory: non_neg_integer(),
          compressed: boolean()
        }

  @doc """
  Lists every ETS table on `node` (including system and private tables - this is an
  observability tool, hiding them helps nobody).
  """
  @spec list_tables(node()) :: {:ok, [table()]} | {:error, term()}
  def list_tables(node) do
    opts = [unread_hidden: false, sys_hidden: false]

    case Rpc.call(node, :observer_backend, :get_table_list, [:ets, opts], @rpc_timeout) do
      tables when is_list(tables) ->
        {:ok, tables |> Enum.map(&decode_table/1) |> Enum.reject(&is_nil/1)}

      {:badrpc, reason} ->
        {:error, reason}

      unexpected ->
        {:error, {:unexpected_reply, unexpected}}
    end
  end

  defp decode_table(proplist) when is_list(proplist) do
    name = Keyword.get(proplist, :name)
    id = Keyword.get(proplist, :id)
    owner = Keyword.get(proplist, :owner)
    reg_name = Keyword.get(proplist, :reg_name)

    %{
      name: name,
      # get_table_list reports :ignore as the id of named tables - the name is their handle.
      handle: if(id == :ignore, do: name, else: id),
      protection: Keyword.get(proplist, :protection),
      owner: owner,
      owner_label: owner_label(owner, reg_name),
      size: Keyword.get(proplist, :size, 0),
      type: Keyword.get(proplist, :type),
      memory: Keyword.get(proplist, :memory, 0),
      compressed: Keyword.get(proplist, :compressed, false)
    }
  end

  # coveralls-ignore-start
  defp decode_table(_unexpected), do: nil
  # coveralls-ignore-stop

  defp owner_label(owner, reg_name) when reg_name in [nil, :ignore], do: inspect(owner)
  defp owner_label(_owner, reg_name), do: inspect(reg_name)

  @doc """
  Whether table content previews are enabled (see the moduledoc - off by default).
  """
  @spec content_inspection_enabled? :: boolean()
  def content_inspection_enabled? do
    Application.get_env(:observer_web, :table_content_inspection, false) == true
  end

  @doc """
  Reads the first objects of a table (bounded, read-only), rendered as inspected strings.

  Returns `{:error, :content_inspection_disabled}` unless content inspection is enabled, and
  `{:error, :not_accessible}` for private tables (or tables that vanished since listing).
  """
  @spec table_content(node(), atom() | reference()) ::
          {:ok, [String.t()]} | {:error, :content_inspection_disabled | :not_accessible}
  def table_content(node, table_handle) do
    if content_inspection_enabled?() do
      fetch_content(node, table_handle)
    else
      {:error, :content_inspection_disabled}
    end
  end

  defp fetch_content(node, table_handle) do
    case Rpc.call(
           node,
           :ets,
           :match_object,
           [table_handle, :_, @content_preview_limit],
           @rpc_timeout
         ) do
      {objects, _continuation} when is_list(objects) ->
        {:ok, Enum.map(objects, &inspect(&1, limit: 50, printable_limit: 512))}

      :"$end_of_table" ->
        {:ok, []}

      _private_or_gone ->
        {:error, :not_accessible}
    end
  end
end
