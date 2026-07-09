defmodule ObserverWeb.Network do
  @moduledoc """
  Samples a node's network endpoints: inet ports (driver-based `gen_tcp`/`gen_udp`/`gen_sctp`
  connections) with their transfer statistics, and NIF-based `socket` module sockets, which port
  listings miss entirely - the web equivalent of observer_cli's Network pane and the observer
  GUI's Ports/Sockets tabs.

  Sampling delegates to `:observer_backend.get_port_list/0` and `get_socket_list/0`
  (runtime_tools, already required on every node for `:dbg` tracing): one RPC round trip each
  returns every endpoint's metadata and counters, regardless of the observer_web version on the
  observed node.

  Transfer counters (`recv_oct`/`send_oct` from `inet:getstat/1`) are cumulative, so ranking by
  throughput uses the delta between two consecutive samples (`rank_ports/4` with the previous
  sample's counters map) - the first sample ranks by the cumulative value.
  """

  alias ObserverWeb.Rpc
  alias ObserverWeb.Tracer.Tool

  @rpc_timeout 10_000

  @type port_row :: %{
          port: port(),
          name: String.t(),
          owner_label: String.t(),
          local: String.t(),
          remote: String.t(),
          recv_oct: non_neg_integer(),
          send_oct: non_neg_integer(),
          recv_diff: non_neg_integer(),
          send_diff: non_neg_integer(),
          queue_size: non_neg_integer(),
          memory: non_neg_integer(),
          inet: Keyword.t()
        }

  @type socket_row :: %{
          id_str: String.t(),
          kind: term(),
          domain: term(),
          type: term(),
          protocol: term(),
          read_bytes: non_neg_integer(),
          write_bytes: non_neg_integer(),
          info: map()
        }

  @doc """
  Collects one sample of the node's inet ports and NIF sockets.

  Nodes running an OTP release without `get_socket_list/0` degrade to an empty socket list
  rather than an error - the inet ports are still reported.
  """
  @spec sample(node()) ::
          {:ok, %{ports: [port_row()], sockets: [socket_row()]}} | {:error, term()}
  def sample(node) do
    case Rpc.call(node, :observer_backend, :get_port_list, [], @rpc_timeout) do
      ports when is_list(ports) ->
        {:ok,
         %{
           ports: ports |> Enum.flat_map(&decode_port/1),
           sockets: sockets(node)
         }}

      {:badrpc, reason} ->
        {:error, reason}

      unexpected ->
        {:error, {:unexpected_reply, unexpected}}
    end
  end

  defp sockets(node) do
    case Rpc.call(node, :observer_backend, :get_socket_list, [], @rpc_timeout) do
      sockets when is_list(sockets) -> Enum.flat_map(sockets, &decode_socket/1)
      # Old OTP releases without get_socket_list/0, or any other failure: the inet ports are
      # the important part, don't fail the whole sample.
      _unavailable -> []
    end
  end

  # Only inet ports belong on the network pane - other ports (files, drivers) are already
  # covered by the Applications page's port inspector.
  defp decode_port(proplist) when is_list(proplist) do
    with inet when is_list(inet) <- Keyword.get(proplist, :inet),
         port when is_port(port) <- Keyword.get(proplist, :port_id) do
      stats = Keyword.get(inet, :statistics, [])
      recv_oct = Keyword.get(stats, :recv_oct, 0)
      send_oct = Keyword.get(stats, :send_oct, 0)

      [
        %{
          port: port,
          name: proplist |> Keyword.get(:name, ~c"") |> to_string(),
          owner_label: proplist |> Keyword.get(:connected) |> owner_label(),
          local: address(inet, :local_address, :local_port),
          remote: address(inet, :remote_address, :remote_port),
          recv_oct: recv_oct,
          send_oct: send_oct,
          recv_diff: recv_oct,
          send_diff: send_oct,
          queue_size: Keyword.get(proplist, :queue_size, 0),
          memory: Keyword.get(proplist, :memory, 0),
          inet: inet
        }
      ]
    else
      _not_inet -> []
    end
  end

  # coveralls-ignore-start
  defp decode_port(_unexpected), do: []
  # coveralls-ignore-stop

  defp owner_label(pid) when is_pid(pid), do: Tool.process_label(pid)
  defp owner_label(other), do: inspect(other)

  defp address(inet, addr_key, port_key) do
    case {Keyword.get(inet, addr_key), Keyword.get(inet, port_key)} do
      {nil, _port} -> "-"
      {addr, nil} -> format_addr(addr)
      {addr, port} -> "#{format_addr(addr)}:#{port}"
    end
  end

  defp format_addr(addr) when is_tuple(addr) do
    case :inet.ntoa(addr) do
      {:error, _} -> inspect(addr)
      formatted -> to_string(formatted)
    end
  end

  defp format_addr(addr), do: inspect(addr)

  defp decode_socket(%{} = info) do
    counters = Map.get(info, :statistics) || %{}

    [
      %{
        id_str: info |> Map.get(:id_str, "") |> to_string(),
        kind: Map.get(info, :kind),
        domain: Map.get(info, :domain),
        type: Map.get(info, :type),
        protocol: Map.get(info, :protocol),
        read_bytes: counter(counters, :read_byte),
        write_bytes: counter(counters, :write_byte),
        info: info
      }
    ]
  end

  # coveralls-ignore-start
  defp decode_socket(_unexpected), do: []
  # coveralls-ignore-stop

  defp counter(counters, key) when is_map(counters) do
    case Map.get(counters, key, 0) do
      value when is_integer(value) -> value
      _unexpected -> 0
    end
  end

  # coveralls-ignore-start
  defp counter(_counters, _key), do: 0
  # coveralls-ignore-stop

  @doc """
  Ranks a sample's inet ports by `sort_by`, keeping the top `limit` rows.

  `previous_counters` is a `%{port => {recv_oct, send_oct}}` map from the preceding sample; each
  row's `recv_diff`/`send_diff` become the delta since then (ports not present before - or on
  the very first sample - keep their cumulative counters).
  """
  @spec rank_ports([port_row()], :recv | :send | :total, pos_integer(), map()) :: [port_row()]
  def rank_ports(ports, sort_by, limit, previous_counters \\ %{}) do
    ports
    |> Enum.map(fn %{port: port, recv_oct: recv, send_oct: send} = row ->
      {prev_recv, prev_send} = Map.get(previous_counters, port, {0, 0})
      %{row | recv_diff: recv - prev_recv, send_diff: send - prev_send}
    end)
    |> Enum.sort_by(&sort_key(&1, sort_by), :desc)
    |> Enum.take(limit)
  end

  defp sort_key(row, :recv), do: row.recv_diff
  defp sort_key(row, :send), do: row.send_diff
  defp sort_key(row, :total), do: row.recv_diff + row.send_diff

  @doc """
  Extracts the `%{port => {recv_oct, send_oct}}` map used as `previous_counters` for the next
  `rank_ports/4` call.
  """
  @spec counters_by_port([port_row()]) :: %{
          optional(port()) => {non_neg_integer(), non_neg_integer()}
        }
  def counters_by_port(ports) do
    Map.new(ports, fn %{port: port, recv_oct: recv, send_oct: send} -> {port, {recv, send}} end)
  end
end
