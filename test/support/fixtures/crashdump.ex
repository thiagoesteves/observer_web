defmodule ObserverWeb.CrashdumpFixtures do
  @moduledoc """
  Generates a real `erl_crash.dump` by crashing a peer node with `erlang:halt/1` - the same
  artifact a production VM leaves behind, so the parser pipeline is tested against the real
  format instead of synthetic fixtures.
  """

  @doc """
  Crashes a throwaway peer node and returns the directory containing its crash dump. The dump
  is generated once per test run and cached under the run's tmp dir.
  """
  @spec ensure_dump!() :: %{dir: String.t(), path: String.t()}
  def ensure_dump! do
    dir = Path.join(System.tmp_dir!(), "observer_web_crashdump_fixture")
    path = Path.join(dir, "erl_crash.dump")

    unless File.exists?(path) do
      File.mkdir_p!(dir)
      generate!(path)
    end

    %{dir: dir, path: path}
  end

  defp generate!(path) do
    {:ok, peer, _peer_node} =
      :peer.start(%{
        name: :"observer_web_crash_#{System.unique_integer([:positive])}",
        connection: :standard_io,
        env: [{~c"ERL_CRASH_DUMP", String.to_charlist(path)}]
      })

    try do
      :peer.call(peer, :erlang, :halt, [~c"observer web test crash"])
    catch
      # The node dies mid-call - that's the point
      _kind, _reason -> :ok
    end

    wait_for_dump(path, 100)
  end

  defp wait_for_dump(path, 0), do: raise("crash dump was not written to #{path}")

  defp wait_for_dump(path, retries) do
    # The dump is complete once the "=end" marker is written
    with true <- File.exists?(path),
         {:ok, content} <- File.read(path),
         true <- String.contains?(content, "=end") do
      :ok
    else
      _not_ready ->
        Process.sleep(100)
        wait_for_dump(path, retries - 1)
    end
  end
end
