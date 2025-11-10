defmodule ObserverWeb.Telemetry.Storage do
  @moduledoc """
  GenServer that collects the telemetry data received
  """
  use GenServer

  alias ObserverWeb.Rpc

  @behaviour ObserverWeb.Telemetry.Adapter

  @storage_table :observer_web_metrics_table
  @mode_key "mode"
  @metric_keys "metric-keys"
  @registry_key "registry-nodes"

  @one_minute_in_milliseconds 60_000
  @retention_data_delete_interval :timer.minutes(1)

  @type t :: %__MODULE__{
          nodes: [atom()],
          node_metric_tables: map(),
          persist_data?: boolean(),
          mode: :local | :broadcast | :observer,
          data_retention_period: nil | non_neg_integer()
        }

  defstruct nodes: [],
            node_metric_tables: %{},
            persist_data?: false,
            mode: :local,
            data_retention_period: nil

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    # Create a general table to store information
    :ets.new(@storage_table, [:set, :protected, :named_table])

    node_self = Node.self()

    mode = Keyword.fetch!(args, :mode)
    data_retention_period = Keyword.fetch!(args, :data_retention_period)

    :ets.insert(@storage_table, {@mode_key, mode})

    persist_data? = fn ->
      if data_retention_period do
        :timer.send_interval(@retention_data_delete_interval, :prune_expired_entries)
        true
      else
        false
      end
    end

    case mode do
      :local ->
        {:ok,
         %__MODULE__{
           nodes: [node_self],
           persist_data?: persist_data?.(),
           node_metric_tables: create_update_metric_table(node_self, %{}),
           mode: mode,
           data_retention_period: data_retention_period
         }}

      :observer ->
        # Subscribe to receive notifications if any node is UP or Down
        :net_kernel.monitor_nodes(true)

        # List all nodes including self()
        nodes = [node_self] ++ Node.list()

        # Subscribe to receive metrics data via PubSub
        Phoenix.PubSub.subscribe(ObserverWeb.PubSub, broadcast_topic())

        {:ok,
         %{
           nodes: nodes,
           persist_data?: persist_data?.(),
           node_metric_tables: Enum.reduce(nodes, %{}, &create_update_metric_table(&1, &2)),
           mode: mode,
           data_retention_period: data_retention_period
         }}

      :broadcast ->
        # NOTE: In Broadcast mode, data is not stored.
        {:ok, %__MODULE__{nodes: [node_self], mode: mode}}
    end
  end

  @impl true
  def handle_cast({:observer_web_telemetry, event}, state) do
    do_handle_metrics(event, state)
  end

  def handle_cast({:update_data_retention_period, retention_period}, state) do
    # If decreasing retention period, immediately prune old data
    if retention_period && state.data_retention_period &&
         retention_period < state.data_retention_period do
      prune_old_data_immediately(state, retention_period)
    end

    {:noreply, %{state | data_retention_period: retention_period}}
  end

  @impl true
  def handle_info({:observer_web_telemetry, event}, state) do
    do_handle_metrics(event, state)
  end

  def handle_info({:nodeup, node}, state) do
    nodes = state.nodes ++ [node]

    if node |> metric_table() |> ets_table_exists?() do
      {:noreply, %{state | nodes: nodes}}
    else
      node_metric_tables = create_update_metric_table(node, state.node_metric_tables)

      {:noreply, %{state | nodes: nodes, node_metric_tables: node_metric_tables}}
    end
  end

  def handle_info(
        {:nodedown, node},
        %{nodes: nodes, persist_data?: persist_data?, node_metric_tables: node_metric_tables} =
          state
      ) do
    metric_table = Map.get(node_metric_tables, node)
    now = System.os_time(:millisecond)
    minute = unix_to_minutes(now)

    node
    |> get_keys_by_node()
    |> Enum.each(fn key ->
      if persist_data? do
        metric_key = metric_key(key, minute)

        data = %ObserverWeb.Telemetry.Data{timestamp: now}

        # credo:disable-for-lines:2
        current_data =
          case :ets.lookup(metric_table, metric_key) do
            [{_, current_list_data}] -> [data | current_list_data]
            _ -> [data]
          end

        :ets.insert(metric_table, {metric_key, current_data})

        notify_new_metric_data(node, key, data)
      end
    end)

    nodes = nodes -- [node]

    {:noreply, %{state | nodes: nodes}}
  end

  def handle_info(
        :prune_expired_entries,
        %{node_metric_tables: tables, data_retention_period: data_retention_period} = state
      ) do
    now_minutes = unix_to_minutes()
    retention_period = trunc(data_retention_period / @one_minute_in_milliseconds)
    deletion_period_to = now_minutes - retention_period - 1
    deletion_period_from = deletion_period_to - 2

    Enum.each(tables, fn {node, table} ->
      node
      |> get_keys_by_node()
      |> Enum.each(&prune_keys(&1, table, deletion_period_from, deletion_period_to))
    end)

    {:noreply, state}
  end

  defp do_handle_metrics(
         %{metrics: metrics, reporter: reporter, measurements: measurements},
         %{nodes: nodes, persist_data?: persist_data?, node_metric_tables: node_metric_tables} =
           state
       ) do
    if reporter in nodes do
      metric_table = Map.get(node_metric_tables, reporter)
      now = System.os_time(:millisecond)
      minute = unix_to_minutes(now)

      keys = get_keys_by_node(reporter)

      new_keys =
        Enum.reduce(metrics, [], fn metric, acc ->
          {key, timed_key, data} = build_telemetry_data(metric, measurements, now, minute)

          if persist_data?, do: ets_append_to_list(metric_table, timed_key, data)

          notify_new_metric_data(reporter, key, data)

          # credo:disable-for-lines:3
          if key in keys do
            acc
          else
            [key | acc]
          end
        end)

      if new_keys != [] do
        :ets.insert(metric_table, {@metric_keys, new_keys ++ keys})

        Phoenix.PubSub.broadcast(
          ObserverWeb.PubSub,
          keys_topic(),
          {:metrics_new_keys, reporter, new_keys}
        )
      end
    end

    {:noreply, state}
  end

  ### ==========================================================================
  ### ObserverWeb.Telemetry.Adapter implementation
  ### ==========================================================================
  @impl true
  def push_data(event) do
    msg = {:observer_web_telemetry, event}

    case cached_mode() do
      :broadcast ->
        Phoenix.PubSub.broadcast(ObserverWeb.PubSub, broadcast_topic(), msg)

      mode when mode in [:local, :observer] ->
        GenServer.cast(__MODULE__, msg)

      _mode_not_defined_yet ->
        :ok
    end
  end

  @impl true
  def subscribe_for_new_keys do
    Phoenix.PubSub.subscribe(ObserverWeb.PubSub, keys_topic())
  end

  @impl true
  def subscribe_for_new_data(node, key) do
    Phoenix.PubSub.subscribe(ObserverWeb.PubSub, metrics_topic(node, key))
  end

  @impl true
  def unsubscribe_for_new_data(node, key) do
    Phoenix.PubSub.unsubscribe(ObserverWeb.PubSub, metrics_topic(node, key))
  end

  @impl true
  def list_data_by_node_key(node, key, options \\ [])

  def list_data_by_node_key(node, key, options) when is_binary(node) do
    node
    |> String.to_existing_atom()
    |> list_data_by_node_key(key, options)
  end

  def list_data_by_node_key(node, key, options) when is_atom(node) do
    case cached_mode() do
      :broadcast ->
        []

      mode when mode in [:local, :observer] ->
        from = Keyword.get(options, :from, 15)
        order = Keyword.get(options, :order, :asc)

        now_minutes = unix_to_minutes()
        from_minutes = now_minutes - from

        metric_table = metric_table(node)

        fetch_data = fn
          :local, node, minute ->
            Rpc.call(node, :ets, :lookup, [metric_table, metric_key(key, minute)], :infinity)

          :observer, _node, minute ->
            if ets_table_exists?(metric_table) do
              :ets.lookup(metric_table, metric_key(key, minute))
            else
              []
            end
        end

        # credo:disable-for-lines:3
        result =
          Enum.reduce(from_minutes..now_minutes, [], fn minute, acc ->
            case fetch_data.(mode, node, minute) do
              [{_, value}] ->
                value ++ acc

              _ ->
                acc
            end
          end)

        if order == :asc, do: Enum.reverse(result), else: result
    end
  end

  @impl true
  def get_keys_by_node(nil), do: []

  def get_keys_by_node(node) do
    case cached_mode() do
      :broadcast ->
        []

      :local ->
        case Rpc.call(node, :ets, :lookup, [metric_table(node), @metric_keys], :infinity) do
          [{_, value}] ->
            value

          # coveralls-ignore-start
          _ ->
            []
            # coveralls-ignore-stop
        end

      :observer ->
        node
        |> metric_table()
        |> ets_lookup_if_exist(@metric_keys, [])
    end
  end

  @impl true
  def list_active_nodes do
    case cached_mode() do
      :broadcast ->
        []

      :local ->
        [Node.self()] ++ Node.list()

      :observer ->
        ets_lookup_if_exist(@storage_table, @registry_key, [])
    end
  end

  @impl true
  def cached_mode do
    ets_lookup_if_exist(@storage_table, @mode_key, nil)
  end

  @impl true
  def update_data_retention_period(retention_period) do
    msg = {:update_data_retention_period, retention_period}

    case cached_mode() do
      mode when mode in [:local, :observer] ->
        GenServer.cast(__MODULE__, msg)

      _mode_with_no_storage ->
        :ok
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp metric_table(node), do: String.to_atom("#{node}::observer-web-metrics")

  defp metric_key(metric, timestamp), do: "#{metric}|#{timestamp}"

  defp unix_to_minutes(time \\ System.os_time(:millisecond)),
    do: trunc(time / @one_minute_in_milliseconds)

  defp ets_table_exists?(table_name) do
    case :ets.info(table_name) do
      :undefined -> false
      _info -> true
    end
  end

  defp ets_lookup_if_exist(table, key, default_return) do
    with true <- ets_table_exists?(table),
         [{_, value}] <- :ets.lookup(table, key) do
      value
    else
      # coveralls-ignore-start
      _ ->
        default_return
        # coveralls-ignore-stop
    end
  end

  defp ets_append_to_list(table, key, new_item) do
    case :ets.lookup(table, key) do
      [{^key, current_list_data}] ->
        updated_list = [new_item | current_list_data]
        :ets.insert(table, {key, updated_list})
        updated_list

      [] ->
        # Key doesn't exist yet, create new list with just this item
        :ets.insert(table, {key, [new_item]})
        [new_item]
    end
  end

  defp prune_old_data_immediately(
         %{node_metric_tables: tables, data_retention_period: old_retention},
         new_retention
       ) do
    now_minutes = unix_to_minutes()
    new_retention_minutes = trunc(new_retention / @one_minute_in_milliseconds)
    old_retention_minutes = trunc(old_retention / @one_minute_in_milliseconds)

    # Delete all data outside the new retention window
    deletion_from = now_minutes - old_retention_minutes - 2
    deletion_to = now_minutes - new_retention_minutes

    Enum.each(tables, fn {node, table} ->
      node
      |> get_keys_by_node()
      |> Enum.each(&prune_keys(&1, table, deletion_from, deletion_to))
    end)
  end

  defp prune_keys(key, table, deletion_period_from, deletion_period_to) do
    Enum.each(deletion_period_from..deletion_period_to, fn timestamp ->
      :ets.delete(table, metric_key(key, timestamp))
    end)
  end

  # NOTE: PubSub topics
  defp keys_topic, do: "metrics::keys"
  defp metrics_topic(node, key), do: "metrics::#{node}::#{key}"
  defp broadcast_topic, do: "metrics::broadcast"

  defp notify_new_metric_data(reporter, key, data) do
    Phoenix.PubSub.broadcast(
      ObserverWeb.PubSub,
      metrics_topic(reporter, key),
      {:metrics_new_data, reporter, key, data}
    )
  end

  defp create_update_metric_table(node, current_map) do
    table = metric_table(node)

    # Create Metric table
    :ets.new(table, [:set, :protected, :named_table])
    :ets.insert(table, {@metric_keys, []})

    # Add node the to registry
    ets_append_to_list(@storage_table, @registry_key, node)

    Map.put(current_map, node, table)
  end

  defp build_telemetry_data(%{name: name} = metric, measurements, now, minute) do
    {name, metric_key(name, minute),
     %ObserverWeb.Telemetry.Data{
       timestamp: now,
       value: metric.value,
       unit: metric.unit,
       tags: metric.tags,
       measurements: measurements
     }}
  end
end
