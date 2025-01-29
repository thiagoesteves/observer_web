defmodule Observer.Web.Authentication do
  @moduledoc """
  This module provides Authentication on mount

  ## References:
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/authentication.ex
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Observer.Web.Resolver

  def on_mount(:default, _params, session, socket) do
    %{"observer" => _observer, "resolver" => resolver, "user" => user} = session

    # Add any configuration here
    conf = nil
    socket = assign(socket, conf: conf, user: user)

    case Resolver.call_with_fallback(resolver, :resolve_access, [user]) do
      {:forbidden, path} ->
        socket =
          socket
          |> put_flash(:error, "Access forbidden")
          |> redirect(to: path)

        {:halt, socket}

      _ ->
        {:cont, socket}
    end
  end
end
