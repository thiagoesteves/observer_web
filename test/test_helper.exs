Application.put_env(:observer_web, Observer.Web.Endpoint,
  check_origin: false,
  http: [port: 4002],
  live_view: [signing_salt: "eX7TFPY6Y/+XQ1o2pOUW3DjgAoXGTAdX"],
  render_errors: [formats: [html: Observer.Web.ErrorHTML], layout: false],
  secret_key_base: "jAu3udxm+8tIRDXLLKo+EupAlEvdLsnNG82O8e9nqylpBM9gP8AjUnZ4PWNttztU",
  server: false,
  url: [host: "localhost"]
)

Application.put_env(:observer_web, ObserverWeb.Rpc, adapter: ObserverWeb.RpcMock)

defmodule Observer.Web.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule LimitedResolver do
  @behaviour Observer.Web.Resolver

  @impl Observer.Web.Resolver
  def resolve_user(_conn), do: %{id: 0}

  @impl Observer.Web.Resolver
  def resolve_access(%{id: 0}), do: {:forbidden, "/"}
  def resolve_access(_user), do: :all
end

defmodule Observer.Web.Test.Router do
  use Phoenix.Router

  import Observer.Web.Router

  pipeline :browser do
    plug :fetch_session
    plug :fetch_flash
  end

  scope "/", ThisWontBeUsed, as: :this_wont_be_used do
    pipe_through :browser

    observer_dashboard("/observer")
    observer_dashboard("/observer-limited", as: :observer_limited, resolver: LimitedResolver)

    observer_dashboard("/observer-private",
      as: :observer_private,
      observer_name: ObserverPrivate,
      resolver: PrivateResolver
    )
  end
end

defmodule Observer.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :observer_web

  socket "/live", Phoenix.LiveView.Socket

  plug Plug.Session,
    store: :cookie,
    key: "_observer_web_key",
    signing_salt: "cuxdCB1L"

  plug Observer.Web.Test.Router
end

Observer.Web.Endpoint.start_link()

ExUnit.start()
