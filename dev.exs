# Development server for Observer Web

# :mnesia is not part of the application's declared dependencies (host releases decide whether
# they ship it), and Mix prunes undeclared OTP applications from the code path (Elixir 1.15+).
# Load it here so the Mnesia browser can be exercised: :mnesia.start() from a remsh, then browse.
Mix.ensure_application!(:mnesia)

# Phoenix

defmodule WebDev.Router do
  use Phoenix.Router, helpers: false

  import Observer.Web.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    observer_dashboard("/observer")
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

Application.put_env(:phoenix, :serve_endpoints, true)
Application.put_env(:phoenix, :persistent, true)

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
