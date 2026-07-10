defmodule ObserverWeb.EtsTest do
  use ExUnit.Case, async: false

  import Mox

  alias ObserverWeb.Ets

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    stub(ObserverWeb.RpcMock, :call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    :ok
  end

  describe "list_tables/1" do
    test "lists named and unnamed tables with their metadata" do
      named = :ets.new(:ets_context_test_named, [:named_table, :public])
      unnamed = :ets.new(:ets_context_test_unnamed, [:public])
      :ets.insert(unnamed, {:a, 1})

      assert {:ok, tables} = Ets.list_tables(Node.self())

      named_table = Enum.find(tables, &(&1.name == :ets_context_test_named))
      assert named_table.handle == :ets_context_test_named
      assert named_table.protection == :public
      assert named_table.type == :set
      assert named_table.size == 0
      assert named_table.memory > 0
      # The owner is this (unregistered) test process
      assert named_table.owner == self()
      assert named_table.owner_label == inspect(self())

      unnamed_table = Enum.find(tables, &(&1.handle == unnamed))
      assert unnamed_table.size == 1
    after
      :ets.delete(:ets_context_test_named)
    end

    test "labels tables owned by registered processes with the process name" do
      assert {:ok, tables} = Ets.list_tables(Node.self())

      # ObserverWeb's own telemetry consumer tables aside, kernel's code server always exists
      ac_tab = Enum.find(tables, &(&1.name == :ac_tab))
      assert ac_tab.owner_label == ":application_controller"
    end

    test "reports rpc failures as errors" do
      stub(ObserverWeb.RpcMock, :call, fn _node, _module, _function, _args, _timeout ->
        {:badrpc, :nodedown}
      end)

      assert {:error, :nodedown} = Ets.list_tables(:unreachable@nohost)
    end
  end

  describe "table_content/2" do
    setup do
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

    test "is disabled by default" do
      refute Ets.content_inspection_enabled?()

      table = :ets.new(:ets_content_disabled_test, [:public])
      :ets.insert(table, {:secret, "value"})

      assert {:error, :content_inspection_disabled} = Ets.table_content(Node.self(), table)
    end

    test "previews a bounded number of inspected objects when enabled" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      table = :ets.new(:ets_content_enabled_test, [:public, :ordered_set])
      for i <- 1..100, do: :ets.insert(table, {i, "value_#{i}"})

      assert {:ok, objects} = Ets.table_content(Node.self(), table)

      # Bounded to the preview limit, not the whole table
      assert length(objects) == 50
      assert Enum.all?(objects, &is_binary/1)
      assert Enum.any?(objects, &(&1 =~ "value_1"))
    end

    test "reports an empty table" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      table = :ets.new(:ets_content_empty_test, [:public])

      assert {:ok, []} = Ets.table_content(Node.self(), table)
    end

    test "reports private tables as not accessible (metadata stays visible)" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      test_pid = self()

      # Owned by another process, so neither the test process nor the rpc worker can read it
      spawn(fn ->
        table = :ets.new(:ets_content_private_test, [:private])
        :ets.insert(table, {:secret, "value"})
        send(test_pid, {:table, table})

        receive do
          :done -> :ok
        end
      end)

      assert_receive {:table, table}

      assert {:error, :not_accessible} = Ets.table_content(Node.self(), table)
    end

    test "reports vanished tables as not accessible" do
      Application.put_env(:observer_web, :table_content_inspection, true)

      table = :ets.new(:ets_content_gone_test, [:public])
      :ets.delete(table)

      assert {:error, :not_accessible} = Ets.table_content(Node.self(), table)
    end
  end
end
