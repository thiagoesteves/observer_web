defmodule TracingWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TracingWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:tracing_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TracingWeb.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: TracingWeb.Finch},
      # Start a worker by calling: TracingWeb.Worker.start_link(arg)
      # {TracingWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      TracingWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TracingWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TracingWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
