defmodule ObserverWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, [name: ObserverWeb.PubSub]},
      ObserverWeb.Tracer.Server,
      ObserverWeb.Telemetry.VmMemory,
      ObserverWeb.Telemetry.Consumer
    ]

    # # See https://hexdocs.pm/elixir/Supervisor.html
    # # for other strategies and supported options
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
