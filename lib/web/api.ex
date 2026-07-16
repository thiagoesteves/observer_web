defmodule Observer.Web.Api do
  @moduledoc """
  Read-only JSON API over the Observer Web collectors, mounted with
  `Observer.Web.Router.observer_api/2`.

  The API is aimed at automation and AI agents: every endpoint returns a bounded, JSON-encoded
  snapshot of the same data the dashboard pages render, collected through the existing RPC
  layer, so it works against any node in the cluster.

  ## Endpoints

  All endpoints accept an optional `node` query parameter (defaults to the local node). The
  value must match a node currently visible in the cluster, anything else is a `404`.

  * `GET /` - available endpoints and visible nodes.
  * `GET /system` - runtime info, VM limits, allocator utilization (`ObserverWeb.SystemInfo`).
  * `GET /processes?sort_by=reductions|memory|message_queue_len&limit=50` - etop-style process
    ranking (`ObserverWeb.Processes`). `reductions` are cumulative since process start.
  * `GET /ets` - every ETS table with size/memory/owner metadata (`ObserverWeb.Ets`).
  * `GET /apps` - running applications with description and version (`ObserverWeb.Apps`).

  Access control goes through the same `Observer.Web.Resolver` used by the dashboard:
  `{:forbidden, _}` access renders a `403`. Since every endpoint is read-only, both `:all` and
  `:read_only` access are accepted.
  """

  @behaviour Plug

  import Plug.Conn

  alias Observer.Web.Resolver
  alias ObserverWeb.Ets
  alias ObserverWeb.Processes
  alias ObserverWeb.SystemInfo

  @endpoints ~w(system processes ets apps)

  @sort_by_values %{
    "reductions" => :reductions,
    "memory" => :memory,
    "message_queue_len" => :message_queue_len
  }

  @default_limit 50
  @max_limit 1_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, action: action, resolver: resolver) do
    conn = fetch_query_params(conn)

    user = Resolver.call_with_fallback(resolver, :resolve_user, [conn])

    case Resolver.call_with_fallback(resolver, :resolve_access, [user]) do
      {:forbidden, _path} ->
        send_json(conn, 403, %{error: "forbidden"})

      _read_only_or_all ->
        dispatch(conn, action)
    end
  end

  defp dispatch(conn, :index) do
    send_json(conn, 200, %{
      endpoints: @endpoints,
      nodes: Enum.map(known_nodes(), &to_string/1)
    })
  end

  defp dispatch(conn, action) do
    case resolve_node(conn.query_params["node"]) do
      {:ok, node} -> render(conn, action, node)
      :error -> send_json(conn, 404, %{error: "unknown node"})
    end
  end

  defp render(conn, :system, node) do
    case SystemInfo.node_info(node) do
      {:ok, node_info} ->
        send_json(conn, 200, %{
          node: to_string(node),
          info: node_info,
          limits: SystemInfo.limits(node),
          allocators: SystemInfo.allocators(node)
        })

      {:error, reason} ->
        send_json(conn, 502, %{error: "could not read node", reason: inspect(reason)})
    end
  end

  defp render(conn, :processes, node) do
    sort_by = Map.get(@sort_by_values, conn.query_params["sort_by"], :reductions)
    limit = parse_limit(conn.query_params["limit"])

    case Processes.sample(node) do
      {:ok, sample} ->
        rows =
          sample
          |> Processes.rank(sort_by, limit)
          |> Enum.map(fn row ->
            row
            |> Map.delete(:reductions_diff)
            |> Map.update!(:pid, &inspect/1)
          end)

        send_json(conn, 200, %{
          node: to_string(node),
          process_count: sample.process_count,
          run_queue: sample.run_queue,
          memory: sample.memory,
          sort_by: sort_by,
          processes: rows
        })

      {:error, reason} ->
        send_json(conn, 502, %{error: "could not read node", reason: inspect(reason)})
    end
  end

  defp render(conn, :ets, node) do
    case Ets.list_tables(node) do
      {:ok, tables} ->
        tables =
          Enum.map(tables, fn table ->
            table
            |> Map.update!(:handle, &inspect/1)
            |> Map.update!(:owner, &inspect/1)
          end)

        send_json(conn, 200, %{node: to_string(node), tables: tables})

      {:error, reason} ->
        send_json(conn, 502, %{error: "could not read node", reason: inspect(reason)})
    end
  end

  defp render(conn, :apps, node) do
    send_json(conn, 200, %{node: to_string(node), applications: ObserverWeb.Apps.list(node)})
  rescue
    # Apps.list is not error-shaped: a node vanishing mid-request surfaces as a raise.
    error -> send_json(conn, 502, %{error: "could not read node", reason: inspect(error)})
  end

  # The node query value only becomes a node if it matches a currently known node - crafted
  # values never reach RPC and never allocate atoms.
  defp resolve_node(nil), do: {:ok, Node.self()}

  defp resolve_node(value) do
    case Enum.find(known_nodes(), &(to_string(&1) == value)) do
      nil -> :error
      node -> {:ok, node}
    end
  end

  defp known_nodes, do: [Node.self() | Node.list()]

  defp parse_limit(value) do
    case Integer.parse(value || "") do
      {limit, ""} when limit > 0 -> min(limit, @max_limit)
      _invalid -> @default_limit
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end
end
