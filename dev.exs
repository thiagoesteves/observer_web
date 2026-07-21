# Development server for Observer Web

# :mnesia and :observer are not part of the application's declared dependencies (host releases
# decide whether they ship them), and Mix prunes undeclared OTP applications from the code path
# (Elixir 1.15+). Load them here so the Mnesia browser and the Crashdump viewer can be
# exercised. Comment out the :observer line to preview the Crashdump "not available" notice.
Mix.ensure_application!(:mnesia)
Mix.ensure_application!(:observer)

# Distributed Erlang: auto-connect to a remote node on boot, so a plain `elixir --sname observer
# --cookie <cookie> -S mix run --no-halt dev.exs` (no iex, nothing to type) still reaches it.
# Requires this VM to be started distributed itself (--sname/--name) and to share the target
# node's cookie (--cookie, or Node.set_cookie/1 beforehand).
if connect_node = System.get_env("OBSERVER_WEB_DEV_CONNECT_NODE") do
  node = String.to_atom(connect_node)

  case Node.connect(node) do
    true ->
      IO.puts("Observer Web dev: connected to #{connect_node}")

    false ->
      IO.puts("Observer Web dev: failed to connect to #{connect_node} (check cookie/network)")

    :ignored ->
      IO.puts("Observer Web dev: not distributed - pass --sname/--name to elixir/iex")
  end
end

# Phoenix

# A deliberately simple custom page exercising the public page API end to end: registered via
# the :pages router option below, it shows up as DEMO in the nav, receives the standard
# dashboard assigns and proves the event flow with a counter button.
defmodule WebDev.DemoPage do
  use Observer.Web.Page

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white dark:bg-gray-800 p-6 text-gray-900 dark:text-white">
      <h2 class="text-xl font-bold mb-2">Demo custom page</h2>
      <div class="text-sm mb-4 text-gray-600 dark:text-gray-300">
        Registered with
        <span class="font-mono">observer_dashboard "/observer", pages: [demo: WebDev.DemoPage]</span>
      </div>

      <div class="flex flex-wrap gap-2 text-xs mb-6">
        <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
          Node: {Node.self()}
        </span>
        <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
          Access: {inspect(@access)}
        </span>
        <span class="px-2 py-1 rounded-full bg-teal-50 border border-teal-300 text-teal-700">
          Theme: {@theme}
        </span>
      </div>

      <button
        phx-click="demo-increment"
        class="px-4 py-2 rounded-lg bg-cyan-500 hover:bg-cyan-600 text-white text-sm font-semibold"
      >
        Clicked {@counter} times
      </button>
    </div>
    """
  end

  @impl Observer.Web.Page
  def handle_mount(socket) do
    socket
    |> Phoenix.Component.assign(:page_title, "Demo")
    |> Phoenix.Component.assign_new(:counter, fn -> 0 end)
  end

  @impl Observer.Web.Page
  def handle_parent_event("demo-increment", _value, socket) do
    {:noreply, Phoenix.Component.assign(socket, :counter, socket.assigns.counter + 1)}
  end

  def handle_parent_event(_event, _value, socket), do: {:noreply, socket}
end

defmodule WebDev.ApiAuth do
  @moduledoc """
  Minimal bearer-token auth guarding the dev server's `observer_api/2` mount, standing in for
  the "pipe_through your own auth" flow described in the JSON API installation guide. This is a
  fixed, printed-to-console dev token only - never reuse this plug outside local development.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    token = Application.fetch_env!(:observer_web, :dev_api_token)

    with ["Bearer " <> provided] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(provided, token) do
      conn
    else
      _unauthorized ->
        conn
        |> put_resp_header("content-type", "application/json; charset=utf-8")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end

defmodule WebDev.Router do
  use Phoenix.Router, helpers: false

  import Observer.Web.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  pipeline :api do
    plug(WebDev.ApiAuth)
  end

  scope "/" do
    pipe_through(:browser)

    observer_dashboard("/observer", pages: [demo: WebDev.DemoPage])
  end

  # A distinct top-level segment, not nested under "/observer": the dashboard mount above owns
  # `/observer/:page` as a catch-all LiveView route, which would otherwise shadow anything
  # placed under "/observer/*" and never reach this pipeline at all.
  scope "/" do
    pipe_through(:api)

    observer_api("/observer-api")
  end
end

defmodule WebDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :observer_web

  socket("/live", Phoenix.LiveView.Socket)
  socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)

  plug(Phoenix.LiveReloader)
  plug(Phoenix.CodeReloader)

  plug(Plug.Session,
    store: :cookie,
    key: "_observer_web_key",
    signing_salt: "/VEDsdfsffMnp5"
  )

  plug(WebDev.Router)
end

defmodule WebDev.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

# Configuration

port = "PORT" |> System.get_env("4000") |> String.to_integer()

# JSON API auth: WebDev.ApiAuth checks incoming requests against this fixed dev token so the
# /observer/api mount (opt-in, see the installation guide) can be exercised locally with curl.
# Override with OBSERVER_WEB_DEV_API_TOKEN; this pattern is dev-only, never reuse it for a real
# deployment.
api_token = System.get_env("OBSERVER_WEB_DEV_API_TOKEN", "observer-dev-token")
Application.put_env(:observer_web, :dev_api_token, api_token)

IO.puts("""
Observer Web dev JSON API token: #{api_token}
  curl -H "Authorization: Bearer #{api_token}" http://localhost:#{port}/observer-api
""")

Application.put_env(:observer_web, WebDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  debug_errors: true,
  http: [port: port],
  live_view: [signing_salt: "eX7TFPY6Y/+XQ1o2pOUW3DjgAoXGTAdX"],
  pubsub_server: ObserverWeb.PubSub,
  render_errors: [formats: [html: WebDev.ErrorHTML], layout: false],
  secret_key_base: "jAu3udxm+8tIRDXLLKo+EupAlEvdLsnNG82O8e9nqylpBM9gP8AjUnZ4PWNttztU",
  url: [host: "localhost"],
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/web/components/.*(ex)$",
      ~r"lib/web/live/.*(ex)$"
    ]
  ]
)

# The crashdump_dirs listing is optional now that dumps can be uploaded straight from the
# browser. Point it at a real directory to exercise the host-dump listing.
Application.put_env(:observer_web, :crashdump_dirs, ["/path/to/dumps/"])
Application.put_env(:phoenix, :serve_endpoints, true)
Application.put_env(:phoenix, :persistent, true)

# Logs page: attach a file-backed :logger handler so the Logs pillar has something to tail.
# Every instance writes to its own random file under the system tmp dir, since multiple nodes
# (e.g. observer + broadcast) are commonly run side by side - the node name keeps the files
# recognizable and the random suffix keeps restarts apart. A heartbeat keeps appending lines so
# REFRESH always has new content; set OBSERVER_WEB_DEV_LOG_HEARTBEAT_MS=0 to silence it, or
# OBSERVER_WEB_DEV_LOG_FILE=false to skip the handler entirely.
if System.get_env("OBSERVER_WEB_DEV_LOG_FILE", "false") == "true" do
  require Logger

  node_slug = node() |> to_string() |> String.replace(~r/[^A-Za-z0-9]+/, "-")
  random_suffix = 3 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  # Literally /tmp (not System.tmp_dir!/0): on macOS the latter resolves to a per-user
  # /var/folders/... path, and a predictable location makes the files easy to find and clean.
  log_file = Path.join("/tmp", "observer_web_dev_#{node_slug}_#{random_suffix}.log")

  # config.exs pins the primary logger level to :warning, which would filter info entries
  # before any handler sees them. Lower the primary level for the dev server and pin the
  # console (default handler) back to :warning, so the terminal stays as quiet as before
  # while the file receives the full info/warning/error mix.
  Logger.configure(level: :info)
  :ok = :logger.set_handler_config(:default, :level, :warning)

  :ok =
    :logger.add_handler(:observer_web_dev_file_log, :logger_std_h, %{
      config: %{file: to_charlist(log_file)},
      # No ANSI colors in the file: the default formatter enables them when the dev server
      # runs in a terminal, which would land escape codes in the log.
      formatter: Logger.Formatter.new(colors: [enabled: false])
    })

  IO.puts("Observer Web dev file logger attached, writing to #{log_file}")

  heartbeat_ms =
    "OBSERVER_WEB_DEV_LOG_HEARTBEAT_MS" |> System.get_env("5000") |> String.to_integer()

  if heartbeat_ms > 0 do
    Task.start(fn ->
      heartbeat_ms
      |> Stream.interval()
      |> Enum.each(fn beat ->
        case rem(beat, 10) do
          # Multi-line entry: exercises the collapse-behind-an-arrow rendering
          9 ->
            Logger.error("""
            dev log heartbeat ##{beat} from #{node()} (sample error)
                ** (RuntimeError) sample multi-line report for the Logs page
                    (observer_web) lib/fake/worker.ex:42: Fake.Worker.run/0
                    (observer_web) lib/fake/server.ex:87: Fake.Server.handle_info/2
                    (stdlib) gen_server.erl:2345: :gen_server.try_handle_info/3
            """)

          # Long single-line entry: exercises truncation and the hover tooltip
          7 ->
            Logger.info(
              "dev log heartbeat ##{beat} from #{node()} with a deliberately long single-line " <>
                "message to check truncation in the Logs page - " <>
                String.duplicate("lorem ipsum dolor sit amet ", 12)
            )

          n when n in [3, 6] ->
            Logger.warning("dev log heartbeat ##{beat} from #{node()}")

          _info ->
            Logger.info("dev log heartbeat ##{beat} from #{node()}")
        end
      end)
    end)
  end
end

Task.async(fn ->
  # Stop the default Telemetry server to start a new one with new defaults
  mode = "OBSERVER_WEB_TELEMETRY_MODE" |> System.get_env("local") |> String.to_atom()

  retention_period =
    "OBSERVER_WEB_TELEMETRY_RETENTION_PERIOD" |> System.get_env("1800000") |> String.to_integer()

  telemetry_module = ObserverWeb.Telemetry.Storage
  :ok = Supervisor.terminate_child(ObserverWeb.Application, telemetry_module)
  :ok = Supervisor.delete_child(ObserverWeb.Application, telemetry_module)

  {:ok, _} =
    Supervisor.start_child(
      ObserverWeb.Application,
      {telemetry_module, [mode: mode, data_retention_period: retention_period]}
    )

  # The scheduler utilization metric is opt-in (see the installation guide) and the application
  # has already booted by the time this script runs, so the producer is started here as an extra
  # child of the telemetry supervisor. Set the interval to 0 to disable it.
  scheduler_interval_ms =
    "OBSERVER_WEB_SCHEDULER_UTILIZATION_INTERVAL_MS"
    |> System.get_env("5000")
    |> String.to_integer()

  if scheduler_interval_ms > 0 do
    {:ok, _} =
      Supervisor.start_child(
        Observer.Web.Telemetry,
        {ObserverWeb.Telemetry.Producer.SchedulerWallTime, interval_ms: scheduler_interval_ms}
      )
  end

  # ETS content previews are opt-in (see the installation guide). The flag is read at request
  # time, so setting it here after boot works - enabled by default in the dev server, set the
  # env to "false" to disable.
  table_content_inspection? =
    "OBSERVER_WEB_TABLE_CONTENT_INSPECTION" |> System.get_env("true") |> String.to_atom()

  Application.put_env(:observer_web, :table_content_inspection, table_content_inspection? == true)

  {:ok, _} = Supervisor.start_child(ObserverWeb.Application, WebDev.Endpoint)

  Process.sleep(:infinity)
end)
