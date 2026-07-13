defmodule ObserverWeb.CrashdumpTest do
  use ExUnit.Case, async: false

  alias ObserverWeb.Crashdump
  alias ObserverWeb.CrashdumpFixtures

  setup do
    original = Application.get_env(:observer_web, :crashdump_dirs)

    # The Crashdump server (and the parser it links) keeps the last loaded dump - restart it so
    # every test starts from a clean :idle state regardless of ordering.
    :ok = Supervisor.terminate_child(ObserverWeb.Application, ObserverWeb.Crashdump.Server)
    {:ok, _pid} = Supervisor.restart_child(ObserverWeb.Application, ObserverWeb.Crashdump.Server)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:observer_web, :crashdump_dirs)
      else
        Application.put_env(:observer_web, :crashdump_dirs, original)
      end
    end)

    :ok
  end

  defp await_loaded do
    receive do
      {:crashdump_progress, {:loaded, _path}} -> :ok
      {:crashdump_progress, {:error, reason}} -> raise "load failed: #{inspect(reason)}"
      {:crashdump_progress, _progress} -> await_loaded()
    after
      30_000 -> raise "timed out waiting for the dump to load"
    end
  end

  test "the parser is available in the test environment" do
    assert Crashdump.available?()
  end

  test "load_upload/1 loads a dump from a path outside the configured directories" do
    %{path: path} = CrashdumpFixtures.ensure_dump!()

    # An uploaded dump is copied to a temp path that is not in any configured directory
    dest = Path.join(System.tmp_dir!(), "cdv_upload_#{System.unique_integer([:positive])}.dump")
    File.cp!(path, dest)

    :ok = Crashdump.subscribe()
    assert :ok = Crashdump.load_upload(dest)
    await_loaded()

    assert {:ok, info} = Crashdump.general_info()
    assert info.slogan =~ "observer web test crash"
  after
    :ok
  end

  test "list_dumps/0 is not configured by default" do
    assert {:error, :not_configured} = Crashdump.list_dumps()
  end

  test "load/1 rejects paths outside the configured directories" do
    %{dir: dir} = CrashdumpFixtures.ensure_dump!()
    Application.put_env(:observer_web, :crashdump_dirs, [dir])

    assert {:error, :unknown_dump} = Crashdump.load("/etc/passwd")
  end

  test "queries before any load report no dump loaded" do
    assert :idle = Crashdump.status()
    assert {:error, :no_dump_loaded} = Crashdump.general_info()
    assert {:error, :no_dump_loaded} = Crashdump.processes()
    assert {:error, :no_dump_loaded} = Crashdump.proc_details("<0.0.0>")
  end

  test "loads a real crash dump and browses its contents" do
    %{dir: dir, path: path} = CrashdumpFixtures.ensure_dump!()
    Application.put_env(:observer_web, :crashdump_dirs, [dir])

    assert {:ok, [dump]} = Crashdump.list_dumps()
    assert dump.path == path
    assert dump.name == "erl_crash.dump"
    assert dump.size > 0

    :ok = Crashdump.subscribe()
    assert :ok = Crashdump.load(path)
    await_loaded()

    assert {:loaded, ^path} = Crashdump.status()

    assert {:ok, info} = Crashdump.general_info()
    assert info.slogan =~ "observer web test crash"
    assert info.num_procs > 0

    assert {:ok, processes} = Crashdump.processes()
    assert length(processes) > 10

    process = hd(processes)
    assert process.pid =~ "<0."
    assert is_integer(process.memory)
    assert is_integer(process.reds)
    assert is_integer(process.msg_q_len)

    assert {:ok, details} = Crashdump.proc_details(process.pid)
    assert details.pid == process.pid
    assert details.state != nil

    assert {:error, :not_found} = Crashdump.proc_details("<0.99999.0>")
  end
end
