defmodule Observer.Web.Helpers do
  @moduledoc false

  alias Phoenix.VerifiedRoutes

  # Routing Helpers

  @doc """
  Prepare parsed params for URI encoding.
  """
  def encode_params(params) do
    for {key, val} <- params, val != nil, val != "" do
      case val do
        [path, frag] when is_list(path) ->
          {key, Enum.join(path, ",") <> "++" <> frag}

        [_ | _] ->
          {key, Enum.join(val, ",")}

        _ ->
          {key, val}
      end
    end
  end

  @doc """
  Construct a path to a dashboard page with optional params.

  Routing is based on a socket and prefix tuple stored in the process dictionary. Proper routing
  can be disabled for testing by setting the value to `:nowhere`.
  """
  def observer_path(route, params \\ %{})

  def observer_path(:root, _params), do: "/"

  def observer_path(route, params) when is_list(route) do
    route
    |> Enum.join("/")
    |> observer_path(params)
  end

  def observer_path(route, params) do
    params =
      params
      |> Enum.sort()
      |> encode_params()

    case Process.get(:routing) do
      {socket, prefix} ->
        VerifiedRoutes.unverified_path(socket, socket.router, "#{prefix}/#{route}", params)

      :nowhere ->
        "/"

      nil ->
        raise RuntimeError, "nothing stored in the :routing key"
    end
  end
end
