defmodule ObserverWeb.MnesiaTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Mnesia

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    original = Application.get_env(:observer_web, :table_content_inspection)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:observer_web, :table_content_inspection)
      else
        Application.put_env(:observer_web, :table_content_inspection, original)
      end
    end)

    :ok
  end

  defp with_mnesia(fun) do
    :ok = :mnesia.start()

    {:atomic, :ok} =
      :mnesia.create_table(:mnesia_browser_test, attributes: [:key, :value], ram_copies: [node()])

    :ok = :mnesia.dirty_write({:mnesia_browser_test, :answer, 42})

    fun.()
  after
    :mnesia.delete_table(:mnesia_browser_test)
    :stopped = :mnesia.stop()
  end

  describe "list_tables/1" do
    test "reports :mnesia_not_running when mnesia is down" do
      assert {:error, :mnesia_not_running} = Mnesia.list_tables(Node.self())
    end

    test "lists tables with storage, size, type and memory" do
      with_mnesia(fn ->
        assert {:ok, tables} = Mnesia.list_tables(Node.self())

        table = Enum.find(tables, &(&1.name == :mnesia_browser_test))
        assert table.storage == :ram_copies
        assert table.size == 1
        assert table.type == :set
        assert table.memory > 0
        assert table.owner_label != ""
        assert table.index == []
      end)
    end

    test "reports rpc failures as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert {:error, :nodedown} = Mnesia.list_tables(:unreachable@nohost)
    end
  end

  describe "table_content/2" do
    test "is disabled by default" do
      with_mnesia(fn ->
        assert {:error, :content_inspection_disabled} =
                 Mnesia.table_content(Node.self(), :mnesia_browser_test)
      end)
    end

    test "previews a ram_copies table through its ets storage when enabled" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      with_mnesia(fn ->
        assert {:ok, objects} = Mnesia.table_content(Node.self(), :mnesia_browser_test)

        assert [object] = objects
        assert object =~ ":answer"
        assert object =~ "42"
      end)
    end

    test "caps the preview for larger tables" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      with_mnesia(fn ->
        for i <- 1..100, do: :ok = :mnesia.dirty_write({:mnesia_browser_test, i, i})

        assert {:ok, objects} = Mnesia.table_content(Node.self(), :mnesia_browser_test)
        assert length(objects) == 50
      end)
    end

    test "reports tables without a local copy as not accessible" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      with_mnesia(fn ->
        assert {:error, :not_accessible} = Mnesia.table_content(Node.self(), :no_such_table)
      end)
    end
  end
end
