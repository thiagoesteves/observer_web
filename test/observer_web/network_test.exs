defmodule ObserverWeb.NetworkTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Network

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    stub(ObserverWeb.RpcMock, :pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    :ok
  end

  describe "sample/1" do
    test "reports inet ports with addresses, owner and transfer counters" do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, listen_port_number} = :inet.port(listen)

      {:ok, client} =
        :gen_tcp.connect(~c"localhost", listen_port_number, [:binary, active: false])

      {:ok, accepted} = :gen_tcp.accept(listen, 1_000)

      :ok = :gen_tcp.send(client, String.duplicate("x", 1_000))
      {:ok, _data} = :gen_tcp.recv(accepted, 1_000, 1_000)

      assert {:ok, %{ports: ports}} = Network.sample(Node.self())

      client_row = Enum.find(ports, &(&1.remote == "127.0.0.1:#{listen_port_number}"))
      assert client_row, "expected the client connection among #{length(ports)} inet ports"

      assert client_row.name == "tcp_inet"
      assert client_row.send_oct >= 1_000
      assert client_row.local =~ "127.0.0.1:"
      # Owned by this (unregistered, plain) test-spawned socket owner: the test process, which
      # carries ExUnit's process label
      assert client_row.owner_label =~ "NetworkTest"

      # Every inet row carries the full inet section for the details panel
      assert Keyword.has_key?(client_row.inet, :statistics)
      assert Keyword.has_key?(client_row.inet, :options)

      :gen_tcp.close(client)
      :gen_tcp.close(accepted)
      :gen_tcp.close(listen)
    end

    test "reports NIF sockets with their counters" do
      {:ok, socket} = :socket.open(:inet, :stream, :tcp)

      assert {:ok, %{sockets: sockets}} = Network.sample(Node.self())

      assert [socket_row | _rest] = sockets
      assert socket_row.id_str != ""
      assert socket_row.domain == :inet
      assert socket_row.type == :stream
      assert socket_row.protocol == :tcp
      assert is_integer(socket_row.read_bytes)
      assert is_integer(socket_row.write_bytes)

      :socket.close(socket)
    end

    test "degrades to an empty socket list when get_socket_list is unavailable" do
      stub(ObserverWeb.RpcMock, :call, fn
        node, :observer_backend, :get_port_list, args, timeout ->
          :rpc.call(node, :observer_backend, :get_port_list, args, timeout)

        _node, :observer_backend, :get_socket_list, _args, _timeout ->
          {:badrpc, {:EXIT, {:undef, []}}}
      end)

      assert {:ok, %{sockets: []}} = Network.sample(Node.self())
    end

    test "reports rpc failures as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert {:error, :nodedown} = Network.sample(:unreachable@nohost)
    end
  end

  describe "rank_ports/4" do
    defp row(port, recv, send) do
      %{
        port: port,
        name: "tcp_inet",
        owner_label: "owner",
        local: "127.0.0.1:1",
        remote: "-",
        recv_oct: recv,
        send_oct: send,
        recv_diff: recv,
        send_diff: send,
        queue_size: 0,
        memory: 0,
        inet: []
      }
    end

    test "ranks by recv/send deltas from the previous sample" do
      ports = [row(:a, 1_000, 10), row(:b, 500, 5_000)]

      # :a received 1000 - 900 = 100 since last sample, :b received 500 - 0 = 500
      previous = %{a: {900, 0}}

      assert [%{port: :b, recv_diff: 500}, %{port: :a, recv_diff: 100}] =
               Network.rank_ports(ports, :recv, 10, previous)

      assert [%{port: :b, send_diff: 5_000}, %{port: :a}] =
               Network.rank_ports(ports, :send, 10, previous)

      # total: a -> 100 + 10 = 110, b -> 500 + 5000 = 5500
      assert [%{port: :b}, %{port: :a}] = Network.rank_ports(ports, :total, 10, previous)
    end

    test "caps at the limit and first sample ranks by cumulative counters" do
      ports = [row(:a, 100, 0), row(:b, 300, 0), row(:c, 200, 0)]

      assert [%{port: :b, recv_diff: 300}, %{port: :c, recv_diff: 200}] =
               Network.rank_ports(ports, :recv, 2)
    end
  end

  test "counters_by_port/1 maps ports to their cumulative counters" do
    ports = [row(:a, 100, 10), row(:b, 200, 20)]

    assert Network.counters_by_port(ports) == %{a: {100, 10}, b: {200, 20}}
  end
end
