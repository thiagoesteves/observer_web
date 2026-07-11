defmodule ObserverWeb.Crashdump do
  @moduledoc """
  Browses `erl_crash.dump` files in the web dashboard - the web equivalent of OTP's
  `crashdump_viewer` GUI, reusing its battle-tested parser (`:crashdump_viewer`, part of the
  `:observer` application) instead of reimplementing the dump format.

  ## Enabling

  The whole feature - including its navigation tab - is **off by default** and turned on with a
  single flag:

      config :observer_web, crashdump: true

  Parsing needs OTP's `:crashdump_viewer` (part of the `:observer` application, which ships with
  OTP but is commonly excluded from releases). No GUI/wx is ever started; only the parsing
  `gen_server` is used. When the flag is on but `:observer` isn't in the release, the page
  explains what to add.

  ## Ingesting a dump

  Two ways, both available once enabled:

    * **Upload** an `erl_crash.dump` straight from the browser (e.g. one pulled off a crashed
      Nerves device) - it's parsed on the dashboard node and the temporary copy is discarded.
    * **Browse** dumps already present on the dashboard host, from directories the host
      explicitly allowlists (never a free path):

          config :observer_web, crashdump_dirs: ["/var/log/my_app/crashdumps"]

  ## Security

  Crash dumps contain everything the VM held at crash time: process states, message queues,
  application data. Directory browsing is limited to the allowlisted directories, uploads are
  size-capped, and dumps are parsed on the dashboard node only - never fetched from remote nodes.
  """

  alias ObserverWeb.Crashdump.Server

  @doc """
  Whether the Crashdump feature is enabled (`config :observer_web, crashdump: true`). Off by
  default; gates both the navigation tab and the page.
  """
  @spec enabled? :: boolean()
  def enabled?, do: Application.get_env(:observer_web, :crashdump, false) == true

  @doc """
  Whether the `:crashdump_viewer` parser is available on this node.
  """
  @spec available? :: boolean()
  def available?, do: Code.ensure_loaded?(:crashdump_viewer)

  @doc """
  Lists the crash dump files found in the configured `:crashdump_dirs` (newest first).
  Returns `{:error, :not_configured}` when no directory is configured - the feature's off state.
  """
  @spec list_dumps() :: {:ok, [map()]} | {:error, :not_configured}
  def list_dumps do
    case Application.get_env(:observer_web, :crashdump_dirs, []) do
      [] ->
        {:error, :not_configured}

      dirs when is_list(dirs) ->
        dumps =
          dirs
          |> Enum.flat_map(&list_dir/1)
          |> Enum.sort_by(& &1.mtime, :desc)

        {:ok, dumps}
    end
  end

  defp list_dir(dir) do
    dir
    |> Path.join("*.dump")
    |> Path.wildcard()
    |> Kernel.++(Path.wildcard(Path.join(dir, "erl_crash.dump")))
    |> Enum.uniq()
    |> Enum.flat_map(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} ->
          [%{path: path, name: Path.basename(path), size: size, mtime: mtime}]

        _unreadable ->
          []
      end
    end)
  end

  @doc """
  Starts loading a dump. Progress and completion are broadcast on the `"crashdump"` PubSub
  topic as `{:crashdump_progress, percent | {:error, reason} | :done}` - subscribe via
  `subscribe/0`. Only paths returned by `list_dumps/0` are accepted.
  """
  @spec load(String.t()) :: :ok | {:error, term()}
  def load(path) do
    with :ok <- check_available(),
         {:ok, dumps} <- list_dumps(),
         %{path: ^path} <- Enum.find(dumps, &(&1.path == path)) || {:error, :unknown_dump} do
      Server.load(path)
    end
  end

  @doc """
  Loads a dump from an uploaded file's already-consumed temporary path. Unlike `load/1` this
  skips the directory allowlist: the path isn't user-supplied text but a temp file LiveView
  produced from a size-capped upload (see `Observer.Web.Crashdump.Page`).
  """
  @spec load_upload(String.t()) :: :ok | {:error, term()}
  def load_upload(path) do
    with :ok <- check_available() do
      Server.load(path)
    end
  end

  defp check_available do
    if available?(), do: :ok, else: {:error, :crashdump_viewer_unavailable}
  end

  @doc """
  The server's current state: `:idle`, `{:loading, path, percent}` or `{:loaded, path}`.
  """
  @spec status() :: :idle | {:loading, String.t(), non_neg_integer()} | {:loaded, String.t()}
  defdelegate status, to: Server

  @doc """
  Subscribes the caller to load progress broadcasts.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(ObserverWeb.PubSub, "crashdump")
  end

  @doc """
  General information about the loaded dump.
  """
  @spec general_info() :: {:ok, map()} | {:error, :no_dump_loaded}
  defdelegate general_info, to: Server

  @doc """
  The loaded dump's process summaries (pid, name, state, current function, message queue
  length, reductions, memory) - the integer fields are sortable.
  """
  @spec processes() :: {:ok, [map()]} | {:error, :no_dump_loaded}
  defdelegate processes, to: Server

  @doc """
  Full details of one process in the loaded dump, by its pid string (e.g. `"<0.42.0>"`),
  including the stack dump and message queue as expandable strings.
  """
  @spec proc_details(String.t()) :: {:ok, map()} | {:error, :no_dump_loaded | :not_found}
  defdelegate proc_details(pid_string), to: Server
end
