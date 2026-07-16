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
  @type os_data :: %{
          os: String.t() | nil,
          load: %{avg1: float(), avg5: float(), avg15: float()} | nil,
          cpus: [%{id: non_neg_integer(), busy_percent: float()}],
          memory:
            %{
              total_bytes: non_neg_integer(),
              available_bytes: non_neg_integer(),
              used_percent: float()
            }
            | nil,
          disks: [
            %{mount: String.t(), total_kbytes: non_neg_integer(), capacity_percent: integer()}
          ]
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

  @doc """
  Operating system level data - load averages, per-CPU utilization, OS memory and disk usage -
  collected through the `os_mon` probes (`:cpu_sup`, `:memsup`, `:disksup`), the same source the
  observer GUI's load charts and LiveDashboard's OS Data page read from.

  Requires the `:os_mon` application to be running on the target node; returns
  `{:error, :os_mon_not_started}` otherwise so callers can hint at adding it to
  `extra_applications`. Individual probes vary per platform, so each section degrades to `nil`
  (or an empty list) instead of failing the whole snapshot.
  """
  @spec os_data(node()) :: {:ok, os_data()} | {:error, :os_mon_not_started | term()}
  def os_data(node) do
    case Rpc.call(node, :erlang, :whereis, [:os_mon_sup], @rpc_timeout) do
      pid when is_pid(pid) ->
        {:ok,
         %{
           os: os_name(node),
           load: load_averages(node),
           cpus: per_cpu_utilization(node),
           memory: os_memory(node),
           disks: disks(node)
         }}

      :undefined ->
        {:error, :os_mon_not_started}

      error ->
        {:error, error}
    end
  end

  defp os_name(node) do
    with {family, name} when family not in [:badrpc, :error] <-
           Rpc.call(node, :os, :type, [], @rpc_timeout),
         version when is_tuple(version) or is_list(version) <-
           Rpc.call(node, :os, :version, [], @rpc_timeout) do
      "#{family}/#{name} #{format_os_version(version)}"
    else
      _unavailable -> nil
    end
  end

  defp format_os_version({major, minor, patch}), do: "#{major}.#{minor}.#{patch}"
  defp format_os_version(version) when is_list(version), do: to_string(version)

  # `:cpu_sup.avg1/0` and friends report the load average multiplied by 256.
  defp load_averages(node) do
    with avg1 when is_integer(avg1) <- Rpc.call(node, :cpu_sup, :avg1, [], @rpc_timeout),
         avg5 when is_integer(avg5) <- Rpc.call(node, :cpu_sup, :avg5, [], @rpc_timeout),
         avg15 when is_integer(avg15) <- Rpc.call(node, :cpu_sup, :avg15, [], @rpc_timeout) do
      %{avg1: load_value(avg1), avg5: load_value(avg5), avg15: load_value(avg15)}
    else
      _unavailable -> nil
    end
  end

  defp load_value(value), do: Float.round(value / 256, 2)

  defp per_cpu_utilization(node) do
    case Rpc.call(node, :cpu_sup, :util, [[:per_cpu]], @rpc_timeout) do
      cpus when is_list(cpus) ->
        Enum.flat_map(cpus, fn
          {id, busy, _non_busy, _misc} when is_number(busy) ->
            [%{id: id, busy_percent: Float.round(busy * 1.0, 2)}]

          _unexpected ->
            []
        end)

      _unavailable ->
        []
    end
  end

  defp os_memory(node) do
    with data when is_list(data) <-
           Rpc.call(node, :memsup, :get_system_memory_data, [], @rpc_timeout),
         total when is_integer(total) and total > 0 <-
           data[:system_total_memory] || data[:total_memory],
         available when is_integer(available) <-
           data[:available_memory] || data[:free_memory] do
      %{
        total_bytes: total,
        available_bytes: available,
        used_percent: Float.round((total - available) / total * 100, 2)
      }
    else
      _unavailable -> nil
    end
  end

  defp disks(node) do
    case Rpc.call(node, :disksup, :get_disk_data, [], @rpc_timeout) do
      disks when is_list(disks) ->
        Enum.flat_map(disks, fn
          {mount, total_kbytes, capacity}
          when is_integer(total_kbytes) and is_integer(capacity) ->
            [%{mount: to_string(mount), total_kbytes: total_kbytes, capacity_percent: capacity}]

          _unexpected ->
            []
        end)

      _unavailable ->
        []
    end
  end

  defp system_info(node, item) do
    Rpc.call(node, :erlang, :system_info, [item], @rpc_timeout)
  end
end
