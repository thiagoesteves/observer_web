defmodule Observer.Web.Router do
  @moduledoc """
  Provides mount points for the Web dashboard with customization.

  ### Customizing with a Resolver Callback Module

  Implementing a `Observer.Web.Resolver` callback module allows you to customize the dashboard
  per-user, i.e. setting access controls.

  As a simple example, let's define a module that makes the dashboard read only:

  ```elixir
  defmodule MyApp.Resolver do
    @behaviour Observer.Web.Resolver

    @impl true
    def resolve_access(_user), do: :read_only
  end
  ```

  Then specify `MyApp.Resolver` as your resolver:

  ```elixir
  scope "/" do
    pipe_through :browser

    observer_dashboard "/observer", resolver: MyApp.Resolver
  end
  ```

  See the `Observer.Web.Resolver` docs for more details.

  ### Running Multiple Dashboards

  A single dashboard may connect to any number of running Observer instances. However, it's also
  possible to change the default instance via the `:observer_name` option. For example, given two
  configured Observer instances, `Observer` and `MyAdmin.Observer`, you can then mount both dashboards in your
  router:

  ```elixir
  scope "/" do
    pipe_through :browser

    observer_dashboard "/observer", observer_name: Observer, as: :observer_dashboard
    observer_dashboard "/admin/observer", observer_name: MyAdmin.Observer, as: :observer_admin_dashboard
  end
  ```

  Note that the default name is `Observer` or the first found instance, setting `observer_name: Observer` in
  the example above was purely for demonstration purposes.

  ### On Mount Hooks

  You can provide a list of hooks to attach to the dashboard's mount lifecycle. Additional hooks
  are prepended before [Observer Web's own Authentication](Observer.Web.Resolver). For example, to run a
  user-fetching hook and an activation checking hook before mount:

  ```elixir
  scope "/" do
    pipe_through :browser

    observer_dashboard "/observer", on_mount: [MyApp.UserHook, MyApp.ActivatedHook]
  end
  ```

  ### Customizing the Socket Connection

  Applications that use a live socket other than "/live" can override the default socket path in
  the router. For example, if your live socket is hosted at `/observer_live`:

  ```elixir
  socket "/observer_live", Phoenix.LiveView.Socket

  scope "/" do
    pipe_through :browser

    observer_dashboard "/observer", socket_path: "/observer_live"
  end
  ```

  If your application is hosted in an environment that doesn't support websockets you can use
  longpolling as an alternate transport. To start, make sure that your live socket is configured
  for longpolling:

  ```elixir
  socket "/live", Phoenix.LiveView.Socket,
    longpoll: [connect_info: [session: @session_options], log: false]
  ```

  Then specify "longpoll" as your transport:

  ```elixir
  scope "/" do
    pipe_through :browser

    observer_dashboard "/observer", transport: "longpoll"
  end
  ```

  ### Content Security Policy

  To secure the dashboard, or comply with an existing CSP within your application, you can specify
  nonce keys for images, scripts and styles.

  You'll configure the CSP nonce assign key in your router, where the dashboard is mounted. For
  example, to use a single nonce for all three asset types:

  ```elixir
  observer_dashboard("/observer", csp_nonce_assign_key: :my_csp_nonce)
  ```

  That instructs the dashboard to extract a generated nonce from the `assigns` map on the plug
  connection, at the `:my_csp_nonce` key.

  Instead, you can specify different keys for each asset type:

  ```elixir
  observer_dashboard("/observer",
    csp_nonce_assign_key: %{
      img: :img_csp_nonce,
      style: :style_csp_nonce,
      script: :script_csp_nonce
    }
  )
  ```
  """

  alias Observer.Web.Resolver

  @default_opts [
    resolver: Resolver,
    socket_path: "/live",
    transport: "websocket"
  ]

  @transport_values ~w(longpoll websocket)

  @doc """
  Defines an observer dashboard route.

  It requires a path where to mount the dashboard at and allows options to customize routing.

  ## Options

  * `:as` — override the route name; otherwise defaults to `:observer_dashboard`

  * `:on_mount` — declares additional module callbacks to be invoked when the dashboard mounts

  * `:observer_name` — name of the Observer instance the dashboard will use for configuration and
    notifications, defaults to `Observer` or the first instance that can be found.

  * `:resolver` — an `Observer.Web.Resolver` implementation used to customize the dashboard's
    functionality.

  * `:socket_path` — a phoenix socket path for live communication, defaults to `"/live"`.

  * `:transport` — a phoenix socket transport, either `"websocket"` or `"longpoll"`, defaults to
    `"websocket"`.

  * `:csp_nonce_assign_key` — CSP (Content Security Policy) keys used to authenticate image,
    style, and script assets by pulling a generated nonce out of the connection's `assigns` map. May
    be `nil`, a single atom, or a map of atoms. Defaults to `nil`.

  ## Examples

  Mount an `observer` dashboard at the path "/observer":

      defmodule MyAppWeb.Router do
        use Phoenix.Router

        import Observer.Web.Router

        scope "/", MyAppWeb do
          pipe_through [:browser]

          observer_dashboard "/observer"
        end
      end

  ## References:
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/router.ex
  """
  defmacro observer_dashboard(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts, route_opts} = Observer.Web.Router.__options__(prefix, opts)

        live_session session_name, session_opts do
          live "/", Observer.Web.IndexLive, :index, route_opts
          live "/:page", Observer.Web.IndexLive, :index, route_opts
        end
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env) do
    Macro.expand(alias, %{env | function: {:observer_dashboard, 2}})
  end

  defp expand_alias(other, _env), do: other

  @doc false
  def __options__(prefix, opts) do
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(opts, &validate_opt!/1)

    on_mount = Keyword.get(opts, :on_mount, []) ++ [Observer.Web.Authentication]

    session_args = [
      prefix,
      opts[:observer_name],
      opts[:resolver],
      opts[:socket_path],
      opts[:transport],
      opts[:csp_nonce_assign_key]
    ]

    session_opts = [
      on_mount: on_mount,
      session: {__MODULE__, :__session__, session_args},
      root_layout: {Observer.Web.Layouts, :root}
    ]

    session_name = Keyword.get(opts, :as, :observer_dashboard)

    {session_name, session_opts, as: session_name}
  end

  @doc false
  def __session__(conn, prefix, observer, resolver, live_path, live_transport, csp_key) do
    user = Resolver.call_with_fallback(resolver, :resolve_user, [conn])

    csp_keys = expand_csp_nonce_keys(csp_key)

    %{
      "prefix" => prefix,
      "observer" => observer,
      "user" => user,
      "resolver" => resolver,
      "access" => Resolver.call_with_fallback(resolver, :resolve_access, [user]),
      "live_path" => live_path,
      "live_transport" => live_transport,
      "csp_nonces" => %{
        img: conn.assigns[csp_keys[:img]],
        style: conn.assigns[csp_keys[:style]],
        script: conn.assigns[csp_keys[:script]]
      }
    }
  end

  defp expand_csp_nonce_keys(nil), do: %{img: nil, style: nil, script: nil}
  defp expand_csp_nonce_keys(key) when is_atom(key), do: %{img: key, style: key, script: key}
  defp expand_csp_nonce_keys(map) when is_map(map), do: map

  defp validate_opt!({:csp_nonce_assign_key, key}) do
    unless is_nil(key) or is_atom(key) or is_map(key) do
      raise ArgumentError, """
      invalid :csp_nonce_assign_key, expected nil, an atom or a map with atom keys,
      got #{inspect(key)}
      """
    end
  end

  defp validate_opt!({:observer_name, name}) do
    unless is_atom(name) do
      raise ArgumentError, """
      invalid :observer_name, expected a module or atom,
      got #{inspect(name)}
      """
    end
  end

  defp validate_opt!({:resolver, resolver}) do
    unless is_atom(resolver) and not is_nil(resolver) do
      raise ArgumentError, """
      invalid :resolver, expected a module that implements the Observer.Web.Resolver behaviour,
      got: #{inspect(resolver)}
      """
    end
  end

  defp validate_opt!({:socket_path, path}) do
    unless is_binary(path) and byte_size(path) > 0 do
      raise ArgumentError, """
      invalid :socket_path, expected a binary URL, got: #{inspect(path)}
      """
    end
  end

  defp validate_opt!({:transport, transport}) do
    unless transport in @transport_values do
      raise ArgumentError, """
      invalid :transport, expected one of #{inspect(@transport_values)},
      got #{inspect(transport)}
      """
    end
  end

  defp validate_opt!(_option), do: :ok
end
