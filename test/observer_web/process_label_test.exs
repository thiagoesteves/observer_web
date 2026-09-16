defmodule ObserverWeb.ProcessLabelTest do
  use ExUnit.Case, async: true

  import Mox

  alias Observer.Web.Mocks.RpcStubber
  alias ObserverWeb.ProcessLabel

  setup :verify_on_exit!

  setup do
    RpcStubber.defaults()
    :ok
  end

  # Spawns a plain (non-proc_lib) process that stays alive until told to stop, so the fallback
  # chain can be exercised without a proc_lib initial call getting in the way.
  defp spawn_plain(fun) do
    test_pid = self()

    pid =
      spawn(fn ->
        fun.()
        send(test_pid, :ready)

        receive do
          :done -> :ok
        end
      end)

    assert_receive :ready
    on_exit(fn -> send(pid, :done) end)

    pid
  end

  describe "resolve/1" do
    test "prefers the registered name over a process label" do
      Process.register(self(), :process_label_registered_test)
      Process.set_label("ignored in favour of the registered name")

      assert ProcessLabel.resolve(self()) == ":process_label_registered_test"
    after
      Process.unregister(:process_label_registered_test)
    end

    test "falls back to the process label for unregistered processes" do
      pid = spawn_plain(fn -> Process.set_label("a binary label") end)

      assert ProcessLabel.resolve(pid) == "a binary label"
    end

    test "inspects non-binary labels" do
      pid = spawn_plain(fn -> Process.set_label({:worker, "acme", 7}) end)

      assert ProcessLabel.resolve(pid) == ~s({:worker, "acme", 7})
    end

    test "falls back to the proc_lib initial call, suffixed with the pid" do
      {:ok, pid} = Task.start(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      label = ProcessLabel.resolve(pid)

      assert label =~ "ProcessLabelTest"
      assert String.ends_with?(label, inspect(pid))
      refute label == inspect(pid)
    end

    test "falls back to the pid when there is nothing else" do
      pid = spawn_plain(fn -> :ok end)

      assert ProcessLabel.resolve(pid) == inspect(pid)
    end

    test "falls back to the pid for dead processes" do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert ProcessLabel.resolve(pid) == inspect(pid)
    end
  end

  describe "from_registered_name/1" do
    test "inspects a real registered name" do
      assert ProcessLabel.from_registered_name(:my_server) == ":my_server"
    end

    test "returns nil for the [] an unregistered process reports" do
      assert ProcessLabel.from_registered_name([]) == nil
    end

    test "returns nil for nil" do
      assert ProcessLabel.from_registered_name(nil) == nil
    end
  end

  describe "from_dictionary/1" do
    test "extracts a binary label as-is" do
      assert ProcessLabel.from_dictionary("$process_label": "plain") == "plain"
    end

    test "inspects a term label" do
      assert ProcessLabel.from_dictionary("$process_label": {:user, "a@b.com"}) ==
               ~s({:user, "a@b.com"})
    end

    test "returns nil when the dictionary holds no label" do
      assert ProcessLabel.from_dictionary("$ancestors": [self()]) == nil
      assert ProcessLabel.from_dictionary([]) == nil
    end

    test "returns nil when there is no dictionary at all" do
      assert ProcessLabel.from_dictionary(nil) == nil
      assert ProcessLabel.from_dictionary(:undefined) == nil
    end
  end

  describe "from_initial_call/3" do
    test "prefers the :\"$initial_call\" dictionary entry over the raw initial call" do
      assert ProcessLabel.from_initial_call(
               ["$initial_call": {MyApp.Worker, :init, 1}],
               {:proc_lib, :init_p, 5},
               self()
             ) == "MyApp.Worker.init/1 #{inspect(self())}"
    end

    test "uses the raw initial call when the dictionary has no entry" do
      assert ProcessLabel.from_initial_call([], {MyApp.Worker, :loop, 2}, self()) ==
               "MyApp.Worker.loop/2 #{inspect(self())}"
    end

    test "returns nil for generic spawn wrappers" do
      assert ProcessLabel.from_initial_call([], {:erlang, :apply, 2}, self()) == nil
      assert ProcessLabel.from_initial_call([], {:proc_lib, :init_p, 5}, self()) == nil
    end

    test "returns nil for anything that is not an MFA" do
      assert ProcessLabel.from_initial_call([], :undefined, self()) == nil
    end
  end
end
