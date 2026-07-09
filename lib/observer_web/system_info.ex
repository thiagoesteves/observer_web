defmodule ObserverWeb.SystemInfo do
  @moduledoc """
  Read-only system snapshot of a node: runtime information, resource counts against their VM
  limits, and per-allocator carrier utilization (the `observer` GUI's System/Memory Allocators
  tabs, observer_cli's Home/System panes).

  Everything is fetched through stdlib-only RPCs (`:erlang.system_info/1` and friends), so it
  works against any node in the cluster regardless of the observer_web version running there.
  """

  alias ObserverWeb.Rpc

  @rpc_timeout 5_000

  @limits [
    {"Processes", :process_count, :process_limit},
    {"Ports", :port_count, :port_limit},
    {"Atoms", :atom_count, :atom_limit},
    {"ETS Tables", :ets_count, :ets_limit}
  ]

  @type limit :: %{
          name: String.t(),
          count: non_neg_integer(),
          limit: pos_integer(),
          percent: float()
        }
  @type allocator :: %{
          name: atom(),
          blocks_size: non_neg_integer(),
          carriers_size: non_neg_integer(),
          utilization_percent: float() | nil
        }

  @doc """
  General runtime information for the node.
  """
  @spec node_info(node()) :: {:ok, map()} | {:error, term()}
  def node_info(node) do
    with otp_release when is_list(otp_release) <- system_info(node, :otp_release),
         erts_version when is_list(erts_version) <- system_info(node, :version),
         architecture when is_list(architecture) <- system_info(node, :system_architecture),
         {uptime_ms, _since_last} <-
           Rpc.call(node, :erlang, :statistics, [:wall_clock], @rpc_timeout) do
      {:ok,
       %{
         otp_release: to_string(otp_release),
         erts_version: to_string(erts_version),
         system_architecture: to_string(architecture),
         schedulers: system_info(node, :schedulers),
         schedulers_online: system_info(node, :schedulers_online),
         uptime_ms: uptime_ms
       }}
    else
      error -> {:error, error}
    end
  end

  @doc """
  Resource counts against their configured VM limits.
  """
  @spec limits(node()) :: [limit()]
  def limits(node) do
    Enum.flat_map(@limits, fn {name, count_key, limit_key} ->
      with count when is_integer(count) <- system_info(node, count_key),
           limit when is_integer(limit) and limit > 0 <- system_info(node, limit_key) do
        [%{name: name, count: count, limit: limit, percent: Float.round(count / limit * 100, 2)}]
      else
        # coveralls-ignore-start
        _unavailable ->
          []
          # coveralls-ignore-stop
      end
    end)
  end

  @doc """
  Carrier utilization per `alloc_util` allocator: how much of the memory reserved in carriers is
  actually occupied by blocks. Low utilization on a busy allocator points at fragmentation - the
  same signal `recon_alloc` and the observer GUI's Memory Allocators tab expose.
  """
  @spec allocators(node()) :: [allocator()]
  def allocators(node) do
    case system_info(node, :alloc_util_allocators) do
      allocs when is_list(allocs) ->
        allocs
        |> Enum.flat_map(&fetch_allocator(node, &1))
        |> Enum.sort_by(& &1.carriers_size, :desc)

      # coveralls-ignore-start
      _unavailable ->
        []
        # coveralls-ignore-stop
    end
  end

  defp fetch_allocator(node, alloc) do
    case Rpc.call(node, :erlang, :system_info, [{:allocator_sizes, alloc}], @rpc_timeout) do
      instances when is_list(instances) ->
        [allocator_utilization(alloc, instances)]

      # coveralls-ignore-start
      _unavailable ->
        []
        # coveralls-ignore-stop
    end
  end

  @doc """
  Reduces one allocator's `:erlang.system_info({:allocator_sizes, alloc})` instance list into
  total block/carrier sizes and a utilization percentage.

  Sizes are reported as `{:size, current, last_max, max}` (or `{:size, current}` on some
  emulator types), under `mbcs`/`sbcs` (multi/single-block carriers) per scheduler instance -
  anything with an unexpected shape is skipped rather than crashing the caller.
  """
  @spec allocator_utilization(atom(), list()) :: allocator()
  def allocator_utilization(alloc, instances) do
    {blocks_size, carriers_size} =
      instances
      |> Enum.flat_map(fn
        {:instance, _n, sections} when is_list(sections) -> sections
        _unexpected -> []
      end)
      |> Enum.reduce({0, 0}, fn
        {carrier_type, values}, {blocks_acc, carriers_acc}
        when carrier_type in [:mbcs, :sbcs] and is_list(values) ->
          {blocks_acc + blocks_size(values), carriers_acc + carriers_size(values)}

        _other_section, acc ->
          acc
      end)

    %{
      name: alloc,
      blocks_size: blocks_size,
      carriers_size: carriers_size,
      utilization_percent:
        if(carriers_size > 0, do: Float.round(blocks_size / carriers_size * 100, 2))
    }
  end

  defp blocks_size(values) do
    values
    |> Enum.flat_map(fn
      {:blocks, blocks} when is_list(blocks) -> blocks
      _other -> []
    end)
    |> Enum.reduce(0, fn
      {_alloc_name, block_values}, acc when is_list(block_values) ->
        acc + current_value(block_values, :size)

      _unexpected, acc ->
        acc
    end)
  end

  defp carriers_size(values), do: current_value(values, :carriers_size)

  defp current_value(values, key) do
    case List.keyfind(values, key, 0) do
      {^key, current, _last_max, _max} when is_integer(current) -> current
      {^key, current} when is_integer(current) -> current
      _missing -> 0
    end
  end

  defp system_info(node, item) do
    Rpc.call(node, :erlang, :system_info, [item], @rpc_timeout)
  end
end
