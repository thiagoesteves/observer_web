defmodule Observer.Web.Helpers do
  @moduledoc false

  alias Phoenix.VerifiedRoutes

  # Routing Helpers

  @doc """
  Prepare parsed params for URI encoding.

  ## Examples

  iex> alias Observer.Web.Helpers
  ...> assert [nodes: "web-1,web-2"] = Helpers.encode_params(nodes: ~w(web-1 web-2))
  ...> assert [args: "a++x"] = Helpers.encode_params(args: [~w(a), "x"])
  ...> assert [args: "a,b++x"] = Helpers.encode_params(args: [~w(a b), "x"])
  ...> assert [args: "a,b,c++x"] = Helpers.encode_params(args: [~w(a b c), "x"])
  ...> assert [args: "a"] = Helpers.encode_params(args: [~w(a)])
  ...> assert [args: :hi] = Helpers.encode_params([args: :hi])
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

  ## Examples

  iex> alias Observer.Web.Helpers
  ...> assert "/" = Helpers.observer_path(:root, :any)
  ...> assert_raise RuntimeError, ~r/nothing stored in the :routing key/, fn -> Helpers.observer_path(nil, ["path", "to", "resource"]) end
  ...> Process.put(:routing, :nowhere)
  ...> assert "/" = Helpers.observer_path(:tracing, ["path", "to", "resource"])
  ...> assert "/" = Helpers.observer_path(["/", "tracing"], ["path", "to", "resource"])
  """
  def observer_path(route, params \\ %{})

  def observer_path(:root, _params), do: "/"

  def observer_path(route, params) when is_list(route) do
    route
    |> Enum.join("/")
    |> observer_path(params)
  end

  # NOTE: Filter page to avoid conflicts with the route path
  def observer_path(route, %{"page" => _name} = params) do
    observer_path(route, Map.delete(params, "page"))
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
