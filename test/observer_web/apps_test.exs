defmodule ObserverWeb.AppsTest do
  use ExUnit.Case, async: true

  import Mox
  alias ObserverWeb.Apps

  alias Observer.Web.Mocks.RpcStubber

  setup :verify_on_exit!

  test "list/0" do
    RpcStubber.defaults()

    assert Enum.find(Apps.list(), &(&1.name == :kernel))
  end

  test "info/0" do
    RpcStubber.defaults()

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info()

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info(Node.self(), :observer_web)

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info(Node.self(), :phoenix_pubsub)

    assert %Apps{id: _, name: _, children: _, symbol: _, lineStyle: _, itemStyle: _} =
             Apps.info(Node.self(), :logger)
  end

  describe "new/1 node naming" do
    setup do
      RpcStubber.defaults()
      :ok
    end

    test "uses the registered name, without the Elixir. prefix" do
      Process.register(self(), MyApp.SomeServer)

      assert %Apps{name: "MyApp.SomeServer"} = Apps.new(%{id: self()})
    after
      Process.unregister(MyApp.SomeServer)
    end

    test "prefers the registered name over a process label" do
      Process.register(self(), :apps_named_and_labelled)
      Process.set_label("ignored in favour of the registered name")

      assert %Apps{name: "apps_named_and_labelled"} = Apps.new(%{id: self()})
    after
      Process.unregister(:apps_named_and_labelled)
    end

    test "falls back to the process label for unregistered processes" do
      test_pid = self()

      pid =
        spawn(fn ->
          Process.set_label({:my_worker, "acme"})
          send(test_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready
      on_exit(fn -> send(pid, :done) end)

      assert %Apps{name: ~s({:my_worker, "acme"})} = Apps.new(%{id: pid})
    end

    test "falls back to the bare pid when a process has neither" do
      test_pid = self()

      pid =
        spawn(fn ->
          send(test_pid, :ready)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :ready
      on_exit(fn -> send(pid, :done) end)

      assert %Apps{name: name} = Apps.new(%{id: pid})
      assert name == pid |> inspect() |> String.trim_leading("#PID")
    end

    test "falls back to the bare pid for a process that has already died" do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert %Apps{name: name} = Apps.new(%{id: pid})
      assert name == pid |> inspect() |> String.trim_leading("#PID")
    end
  end
end
