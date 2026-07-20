defmodule Observer.Web.ApiTest do
  use Observer.Web.ConnCase, async: false

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias Observer.Web.Mocks.TelemetryStubber

  setup :set_mox_global

  setup do
    RpcStubber.defaults()
    TelemetryStubber.defaults()

    :ok
  end

  test "GET / lists endpoints and nodes", %{conn: conn} do
    conn = get(conn, "/observer-api/")

    assert %{"endpoints" => endpoints, "nodes" => nodes} = json_response(conn, 200)
    assert "system" in endpoints
    assert "processes" in endpoints
    assert to_string(Node.self()) in nodes
  end

  test "GET /system returns the runtime snapshot", %{conn: conn} do
    conn = get(conn, "/observer-api/system")

    assert %{"node" => node, "info" => info, "limits" => limits, "allocators" => allocators} =
             json_response(conn, 200)

    assert node == to_string(Node.self())
    assert info["otp_release"] == to_string(:erlang.system_info(:otp_release))
    assert Enum.any?(limits, &(&1["name"] == "Processes"))
    assert Enum.any?(allocators, &(&1["name"] == "binary_alloc"))
  end

  test "GET /processes ranks processes with bounded limit", %{conn: conn} do
    conn = get(conn, "/observer-api/processes?sort_by=memory&limit=5")

    assert %{"processes" => rows, "sort_by" => "memory", "process_count" => count} =
             json_response(conn, 200)

    assert count > 0
    assert length(rows) == 5

    memories = Enum.map(rows, & &1["memory"])
    assert memories == Enum.sort(memories, :desc)

    assert %{"pid" => "#PID" <> _rest, "name" => _name} = hd(rows)
    refute Map.has_key?(hd(rows), "reductions_diff")
  end

  test "GET /processes falls back to defaults on invalid params", %{conn: conn} do
    conn = get(conn, "/observer-api/processes?sort_by=bogus&limit=bogus")

    assert %{"sort_by" => "reductions", "processes" => rows} = json_response(conn, 200)
    assert length(rows) <= 50
  end

  test "GET /ets lists tables with serialized owners", %{conn: conn} do
    conn = get(conn, "/observer-api/ets")

    assert %{"tables" => tables} = json_response(conn, 200)
    assert tables != []
    assert %{"name" => _name, "owner" => "#PID" <> _rest, "size" => _size} = hd(tables)
  end

  test "GET /apps lists running applications", %{conn: conn} do
    conn = get(conn, "/observer-api/apps")

    assert %{"applications" => apps} = json_response(conn, 200)
    assert Enum.any?(apps, &(&1["name"] == "observer_web"))
    assert %{"version" => _version, "description" => _description} = hd(apps)
  end

  test "unknown nodes are rejected with a 404", %{conn: conn} do
    conn = get(conn, "/observer-api/system?node=unknown@nohost")

    assert %{"error" => "unknown node"} = json_response(conn, 404)
  end

  test "unreachable nodes are reported with a 502", %{conn: conn} do
    stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
      {:badrpc, :nodedown}
    end)

    conn = get(conn, "/observer-api/system")

    assert %{"error" => "could not read node"} = json_response(conn, 502)
  end

  test "forbidden access renders a 403", %{conn: conn} do
    conn = get(conn, "/observer-api-limited/system")

    assert %{"error" => "forbidden"} = json_response(conn, 403)
  end

  test "the api routes are not shadowed by the dashboard", %{conn: conn} do
    conn = get(conn, "/observer-api-limited/")

    assert json_response(conn, 403)
  end
end
