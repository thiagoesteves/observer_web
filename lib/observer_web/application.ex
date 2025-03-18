defmodule ObserverWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import ObserverWeb.Macros

  @impl true
  def start(_type, _args) do
    children =
      [
        Observer.Web.Telemetry,
        ObserverWeb.Tracer.Server,
        {Phoenix.PubSub, [name: ObserverWeb.PubSub]}
      ] ++ telemetry_servers()

    # # See https://hexdocs.pm/elixir/Supervisor.html
    # # for other strategies and supported options
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  # NOTE: DO NOT start these servers when running tests.
  if_not_test do
    defp telemetry_servers,
      do: [
        ObserverWeb.Telemetry.Storage
      ]
  else
    defp telemetry_servers, do: []
  end
end
