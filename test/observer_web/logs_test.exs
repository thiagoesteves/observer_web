defmodule ObserverWeb.LogsTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Logs

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    :ok
  end

  describe "list_handlers/1" do
    test "lists file-backed logger handlers and skips console handlers" do
      path = scratch_path("list_handlers.log")

      :ok =
        :logger.add_handler(:observer_web_logs_test, :logger_std_h, %{
          config: %{file: to_charlist(path)}
        })

      on_exit(fn ->
        :logger.remove_handler(:observer_web_logs_test)
        File.rm(path)
      end)

      handlers = Logs.list_handlers(Node.self())

      assert %{id: :observer_web_logs_test, module: :logger_std_h, file: ^path} =
               Enum.find(handlers, &(&1.id == :observer_web_logs_test))

      refute Enum.any?(handlers, &(&1.id == :default))
    end

    test "returns an empty list when the node is unreachable" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert Logs.list_handlers(:unreachable@nohost) == []
    end
  end

  describe "tail/3" do
    setup do
      path = scratch_path("tail.log")

      stub(ObserverWeb.RpcMock, :call, fn
        _node, :logger, :get_handler_config, [], _timeout ->
          [
            %{id: :file_handler, module: :logger_std_h, config: %{file: to_charlist(path)}},
            %{id: :default, module: :logger_std_h, config: %{type: :standard_io}}
          ]

        node, module, function, args, timeout ->
          :rpc.call(node, module, function, args, timeout)
      end)

      on_exit(fn -> File.rm(path) end)

      %{path: path}
    end

    test "reads the whole file when it fits in max_bytes", %{path: path} do
      content = Enum.map_join(1..10, "", &"line #{&1}\n")
      File.write!(path, content)

      assert {:ok, tail} = Logs.tail(Node.self(), path, 4_096)

      assert tail.content == content
      assert tail.size == byte_size(content)
      refute tail.truncated?
    end

    test "bounds the read and drops the partial first line when truncated", %{path: path} do
      content = Enum.map_join(1..100, "", &"line #{&1}\n")
      File.write!(path, content)

      assert {:ok, tail} = Logs.tail(Node.self(), path, 128)

      assert tail.truncated?
      assert tail.size == byte_size(content)
      assert byte_size(tail.content) < 128
      assert String.starts_with?(tail.content, "line ")
      assert String.ends_with?(tail.content, "line 100\n")
    end

    test "tails an empty file", %{path: path} do
      File.write!(path, "")

      assert {:ok, %{content: "", size: 0, truncated?: false}} =
               Logs.tail(Node.self(), path, 128)
    end

    test "rejects files that do not belong to a logger handler" do
      assert {:error, :not_a_logger_file} = Logs.tail(Node.self(), "/etc/passwd", 128)
    end

    test "reports missing files", %{path: path} do
      File.rm(path)

      assert {:error, :enoent} = Logs.tail(Node.self(), path, 128)
    end

    test "reports rpc failures", %{path: path} do
      File.write!(path, "data\n")

      stub(ObserverWeb.RpcMock, :call, fn
        _node, :logger, :get_handler_config, [], _timeout ->
          [%{id: :file_handler, module: :logger_std_h, config: %{file: to_charlist(path)}}]

        _node, :erl_eval, :exprs, _args, _timeout ->
          {:badrpc, :nodedown}
      end)

      assert {:error, {:badrpc, :nodedown}} = Logs.tail(Node.self(), path, 128)
    end
  end

  defp scratch_path(name) do
    dir = Path.join(System.tmp_dir!(), "observer_web_logs_test")
    File.mkdir_p!(dir)

    Path.join(dir, "#{System.unique_integer([:positive])}_#{name}")
  end
end
