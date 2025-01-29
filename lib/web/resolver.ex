defmodule Observer.Web.Resolver do
  @moduledoc """
  Web customization is done through a callback module that implements the this behaviour.

  ## Usage

  Each callback is optional and resolution falls back to the default implementation when a
  callback is omittied. Here is an example implementation that defines all callbacks with their
  default values for reference:

  ```elixir
  defmodule MyApp.Resolver do
    @behaviour Observer.Web.Resolver

    @impl true
    def resolve_user(_conn), do: nil

    @impl true
    def resolve_access(_user), do: :all
  end
  ```

  To use a resolver such as `MyApp.Resolver` defined above, you pass it through as an option to
  `observer_dashboard/2` in your application's router:

  ```elixir
  scope "/" do
    pipe_through :browser

    observer_dashboard "/observer", resolver: MyApp.Resolver
  end
  ```

  ## Overview

  Details about each callback's functionality can be found in the callback docs. Here's a quick
  summary of each callback and its purpose:

  * [Current User](#c:resolve_user/1)—Extract the current user for access controls when the
  dashboard mounts.

  * [Action Controls](#c:resolve_access/1)—Restrict which operations users may perform or forbid
  access to the dashboard.

  ## Authentication

  By combining `resolver_user/1` and `resolve_access/1` callbacks it's possible to build an
  authenticaiton solution around the dashboard. For example, this resolver extracts the
  `current_user` from the conn's assigns map and then scopes their access based on role. If it is
  a standard user or `nil` then they're redirected to `/login` when the dashboard mounts.

  ```elixir
  defmodule MyApp.Resolver do
    @behaviour Observer.Web.Resolver

    @impl true
    def resolve_user(conn) do
      conn.assigns.current_user
    end

    @impl true
    def resolve_access(user) do
      case user do
        %{admin?: true} -> :all
        %{staff?: true} -> :read_only
        _ -> {:forbidden, "/login"}
      end
    end
  end
  ```

  ## References:
   * https://github.com/oban-bg/oban_web/blob/main/lib/oban/web/resolver.ex
  """

  @type access :: :all | :read_only | {:forbidden, Path.t()}

  @type user :: term()

  @doc """
  Extract the current user from a `Plug.Conn` when the dashboard mounts.

  The extracted user is passed to all of the other callback functions, allowing you to customize the
  dashboard per user or role.

  This callback is expected to return `nil`, a map or a struct. However, the resolved user is only
  passed to other functions in the `Resolver` and as part of the metadata for audit events, so
  you're free to use any data type you like.

  ## Examples

  Extract the user from the `assigns` map in a typical plug based auth setup:

      def resolve_user(conn) do
        conn.assigns.current_user
      end

  """
  @callback resolve_user(conn :: Plug.Conn.t()) :: user()

  @doc """
  Determine the appropriate access level for a user.

  During normal operation users can modify running queues and interact with jobs through the
  dashboard. In some situations actions such as pausing a queue may be undesired, or even
  dangerous for operations.

  Through this callback you can tailor precisely which actions the current user can do. The
  default access level is `:all`, which permits _all_ users to do any action.

  Returning `{:forbidden, path}` prevents loading the dashboard entirely and redirects the user to
  the provided path.

  The available fine grained access controls are:

  * `:pause_queues`
  * `:scale_queues`
  * `:cancel_jobs`
  * `:delete_jobs`
  * `:retry_jobs`

  Actions which aren't listed are considered disabled.

  ## Examples

  To set the dashboard read only and prevent users from performing any actions at all:

      def resolve_access(_user), do: :read_only

  Forbid any user that isn't an admin and redirect them to the root:

      def resolve_access(user) do
        if user.admin?, do: :all, else: {:forbidden, "/"}
      end

  Alternatively, you can use the resolved `user` to allow admins write access and keep all other
  users read only:

      def resolve_access(user) do
        if user.admin?, do: :all, else: :read_only
      end

  You can also specify fine grained access for each of the possible dashboard actions.

      def resolve_access(user) do
        if user.admin? do
          [cancel_jobs: true, delete_jobs: true, retry_jobs: true]
        else
          :read_only
        end
      end
  """
  @callback resolve_access(user()) :: access()

  @optional_callbacks resolve_user: 1,
                      resolve_access: 1

  @doc false
  def call_with_fallback(resolver, fun, args) when is_atom(fun) and is_list(args) do
    resolver = if function_exported?(resolver, fun, length(args)), do: resolver, else: __MODULE__

    apply(resolver, fun, args)
  end

  @doc false
  def resolve_user(_conn), do: nil

  @doc false
  def resolve_access(_user), do: :all
end
