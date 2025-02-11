# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

if config_env() == :dev do
  config :esbuild,
    version: "0.17.11",
    default: [
      args: ~w(
        assets/js/app.js
        --bundle
        --minify
        --outdir=priv/static/
      )
    ]

  config :tailwind,
    version: "3.4.0",
    default: [
      args: ~w(
        --config=tailwind.config.js
        --minify
        --input=css/app.css
        --output=../priv/static/app.css
      ),
      cd: Path.expand("../assets", __DIR__)
    ]
end

# Configures Elixir's Logger
config :logger, level: :warning
config :logger, :console, format: "[$level] $message\n"

config :phoenix, stacktrace_depth: 20

# Rpc Adapter
config :observer_web, ObserverWeb.Rpc, adapter: ObserverWeb.Rpc.Local

# Telemetry Adapter
config :observer_web, ObserverWeb.Telemetry, adapter: ObserverWeb.Telemetry.Consumer
