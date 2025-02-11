defmodule ObserverWeb.Telemetry.Consumer do
  @moduledoc """
  GenServer that collects the telemetry data received
  """
  use GenServer

  alias ObserverWeb.Rpc

  @behaviour ObserverWeb.Telemetry.Adapter

  @metric_keys "metric-keys"
  @metric_table :observer_web_metrics

  @one_minute_in_milliseconds 60_000
  @retention_data_delete_interval :timer.minutes(1)

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    node = Node.self()

    # Create metric tables for the node
    :ets.new(@metric_table, [:set, :protected, :named_table])
    :ets.insert(@metric_table, {@metric_keys, []})

    persist_data? =
      if data_retention_period() do
        :timer.send_interval(@retention_data_delete_interval, :prune_expired_entries)
        true
      else
        false
      end

    {:ok, %{node: node, persist_data?: persist_data?}}
  end

  @impl true
  def handle_cast(
        {:observer_web_telemetry,
         %{metrics: metrics, reporter: reporter, measurements: measurements}},
        %{node: node, persist_data?: persist_data?} = state
      )
      when reporter in [node] do
    now = System.os_time(:millisecond)
    minute = unix_to_minutes(now)

    keys = get_keys_by_node(reporter)

    new_keys =
      Enum.reduce(metrics, [], fn metric, acc ->
        {key, timed_key, data} = build_telemetry_data(metric, measurements, now, minute)

        # credo:disable-for-lines:3
        if persist_data? do
          current_data =
            case :ets.lookup(@metric_table, timed_key) do
              [{_, current_list_data}] -> [data | current_list_data]
              _ -> [data]
            end

          :ets.insert(@metric_table, {timed_key, current_data})
        end

        Phoenix.PubSub.broadcast(
          ObserverWeb.PubSub,
          metrics_topic(reporter, key),
          {:metrics_new_data, reporter, key, data}
        )

        if key in keys do
          acc
        else
          [key | acc]
        end
      end)

    if new_keys != [] do
      :ets.insert(@metric_table, {@metric_keys, new_keys ++ keys})

      Phoenix.PubSub.broadcast(
        ObserverWeb.PubSub,
        keys_topic(),
        {:metrics_new_keys, reporter, new_keys}
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:prune_expired_entries, state) do
    now_minutes = unix_to_minutes()
    retention_period = trunc(data_retention_period() / @one_minute_in_milliseconds)
    deletion_period_to = now_minutes - retention_period - 1
    deletion_period_from = deletion_period_to - 2

    prune_keys = fn key ->
      Enum.each(deletion_period_from..deletion_period_to, fn timestamp ->
        :ets.delete(@metric_table, metric_key(key, timestamp))
      end)
    end

    Node.self()
    |> get_keys_by_node()
    |> Enum.each(&prune_keys.(&1))

    {:noreply, state}
  end

  ### ==========================================================================
  ### Deployex.Telemetry.Adapter implementation
  ### ==========================================================================
  @impl true
  def push_data(event) do
    GenServer.cast(__MODULE__, {:observer_web_telemetry, event})
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
    from = Keyword.get(options, :from, 15)
    order = Keyword.get(options, :order, :asc)

    now_minutes = unix_to_minutes()
    from_minutes = now_minutes - from

    result =
      Enum.reduce(from_minutes..now_minutes, [], fn minute, acc ->
        case Rpc.call(
               node,
               :ets,
               :lookup,
               [@metric_table, metric_key(key, minute)],
               :infinity
             ) do
          [{_, value}] ->
            value ++ acc

          _ ->
            acc
        end
      end)

    if order == :asc, do: Enum.reverse(result), else: result
  end

  @impl true
  def get_keys_by_node(nil), do: []

  def get_keys_by_node(node) do
    case Rpc.call(node, :ets, :lookup, [@metric_table, @metric_keys], :infinity) do
      [{_, value}] ->
        value

      # coveralls-ignore-start
      _ ->
        []
        # coveralls-ignore-stop
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp data_retention_period,
    do:
      Application.get_env(:observer_web, ObserverWeb.Telemetry)[:data_retention_period] ||
        :timer.minutes(1)

  defp metric_key(metric, timestamp), do: "#{metric}|#{timestamp}"

  defp unix_to_minutes(time \\ System.os_time(:millisecond)),
    do: trunc(time / @one_minute_in_milliseconds)

  defp keys_topic, do: "metrics::keys"
  defp metrics_topic(node, key), do: "metrics::#{node}::#{key}"

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
