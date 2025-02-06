defmodule Observer.Web.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Observer.Web.Router
  alias Plug.Conn

  defmodule Resolver do
    @behaviour Observer.Web.Resolver

    @impl true
    def resolve_user(conn) do
      conn.private.current_user
    end

    @impl true
    def resolve_access(user) do
      if user.admin? do
        :all
      else
        :read_only
      end
    end
  end

  describe "__options__" do
    test "setting default options in the router module" do
      {session_name, session_opts, route_opts} = Router.__options__("/observer", [])

      assert session_name == :observer_dashboard
      assert route_opts[:as] == :observer_dashboard
      assert session_opts[:root_layout] == {Observer.Web.Layouts, :root}
    end

    test "passing the transport through to the session" do
      assert %{"live_transport" => "longpoll"} = options_to_session(transport: "longpoll")
    end

    test "passing the live socket path through to the session" do
      assert %{"live_path" => "/alt"} = options_to_session(socket_path: "/alt")
    end

    test "passing csp nonce assign keys to the session" do
      assert %{"csp_nonces" => nonces} = options_to_session(csp_nonce_assign_key: nil)

      assert %{img: nil, style: nil, script: nil} = nonces

      assert %{"csp_nonces" => %{img: "abc", style: "abc", script: "abc"}} =
               :get
               |> conn("/observer")
               |> Plug.Conn.assign(:my_nonce, "abc")
               |> options_to_session(csp_nonce_assign_key: :my_nonce)
    end

    test "passing a resolver module through to the session" do
      conn =
        :get
        |> conn("/observer")
        |> Conn.put_private(:current_user, %{id: 1, admin?: false})

      session = options_to_session(conn, resolver: Resolver)

      assert %{"access" => :read_only, "user" => %{id: 1}} = session
    end

    test "passing additional on_mount hooks through to session opts" do
      {_name, sess_opts, _opts} = Router.__options__("/observer", [])

      assert [Observer.Web.Authentication] = Keyword.get(sess_opts, :on_mount)

      {_name, sess_opts, _opts} = Router.__options__("/observer", on_mount: [My.Hook])

      assert [My.Hook, Observer.Web.Authentication] = Keyword.get(sess_opts, :on_mount)
    end

    test "validating observer name values" do
      assert_raise ArgumentError, ~r/invalid :observer_name/, fn ->
        Router.__options__("/observer", observer_name: "MyApp.Observer")
      end
    end

    test "validating socket_path values" do
      assert_raise ArgumentError, ~r/invalid :socket_path/, fn ->
        Router.__options__("/observer", socket_path: :live)
      end
    end

    test "validating transport values" do
      assert_raise ArgumentError, ~r/invalid :transport/, fn ->
        Router.__options__("/observer", transport: "webpoll")
      end
    end

    test "validating resolve_user values" do
      assert_raise ArgumentError, ~r/invalid :resolver/, fn ->
        Router.__options__("/observer", resolver: nil)
      end
    end
  end

  defp options_to_session(opts) do
    :get
    |> conn("/observer")
    |> options_to_session(opts)
  end

  defp options_to_session(conn, opts) do
    {_name, sess_opts, _opts} = Router.__options__("/observer", opts)

    {Router, :__session__, session_opts} = Keyword.get(sess_opts, :session)

    apply(Router, :__session__, [conn | session_opts])
  end
end
