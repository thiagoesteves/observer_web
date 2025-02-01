Application.put_env(:tracing_web, Tracing.Web.Endpoint,
  check_origin: false,
  http: [port: 4002],
  live_view: [signing_salt: "eX7TFPY6Y/+XQ1o2pOUW3DjgAoXGTAdX"],
  render_errors: [formats: [html: Tracing.Web.ErrorHTML], layout: false],
  secret_key_base: "jAu3udxm+8tIRDXLLKo+EupAlEvdLsnNG82O8e9nqylpBM9gP8AjUnZ4PWNttztU",
  server: false,
  url: [host: "localhost"]
)

Application.put_env(:tracing_web, TracingWeb.Rpc, adapter: TracingWeb.RpcMock)

defmodule Tracing.Web.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule LimitedResolver do
  @behaviour Tracing.Web.Resolver

  @impl Tracing.Web.Resolver
  def resolve_user(_conn), do: %{id: 0}

  @impl Tracing.Web.Resolver
  def resolve_access(%{id: 0}), do: {:forbidden, "/"}
  def resolve_access(_user), do: :all
end

defmodule Tracing.Web.Test.Router do
  use Phoenix.Router

  import Tracing.Web.Router

  pipeline :browser do
    plug :fetch_session
    plug :fetch_flash
  end

  scope "/", ThisWontBeUsed, as: :this_wont_be_used do
    pipe_through :browser

    tracing_dashboard("/tracing")
    tracing_dashboard("/tracing-limited", as: :tracing_limited, resolver: LimitedResolver)

    tracing_dashboard("/tracing-private",
      as: :tracing_private,
      tracing_name: TracingPrivate,
      resolver: PrivateResolver
    )
  end
end

defmodule Tracing.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :tracing_web

  socket "/live", Phoenix.LiveView.Socket

  plug Plug.Session,
    store: :cookie,
    key: "_tracing_web_key",
    signing_salt: "cuxdCB1L"

  plug Tracing.Web.Test.Router
end

Tracing.Web.Endpoint.start_link()

ExUnit.start()
