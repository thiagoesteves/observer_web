defmodule ObserverWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [ObserverWeb.Server]

    # # See https://hexdocs.pm/elixir/Supervisor.html
    # # for other strategies and supported options
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
