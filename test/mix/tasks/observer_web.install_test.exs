defmodule Mix.Tasks.ObserverWeb.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test
  alias Mix.Tasks.ObserverWeb.Install.Docs

  test "installation adds the route the necessary setup to the router" do
    test_project()
    |> Igniter.Project.Module.create_module(TestWeb.Router, """
    use TestWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :put_root_layout, {DevWeb.LayoutView, :root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    pipeline :api do
      plug :accepts, ["json"]
    end

    # Enable LiveDashboard and Swoosh mailbox preview in development
    if Application.compile_env(:test, :dev_routes) do
      # If you want to use the LiveDashboard in production, you should put
      # it behind authentication and allow only admins to access it.
      # If your application does not have an admins-only section yet,
      # you can use Plug.BasicAuth to set up some basic authentication
      # as long as you are also using SSL (which you should anyway).
      import Phoenix.LiveDashboard.Router

      scope "/dev" do
        pipe_through :browser

        live_dashboard "/dashboard", metrics: testWeb.Telemetry
        forward "/mailbox", Plug.Swoosh.MailboxPreview
      end
    end
    """)
    |> apply_igniter!()
    |> Igniter.compose_task("observer_web.install")
    |> assert_has_patch("lib/test_web/router.ex", """
         ...|
     2  2   |  use TestWeb, :router
     3  3   |
        4 + |  import Observer.Web.Router
        5 + |
     4  6   |  pipeline :browser do
     5  7   |    plug(:accepts, ["html"])
         ...|
    30 32   |      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    31 33   |    end
       34 + |
       35 + |    scope "/" do
       36 + |      pipe_through(:browser)
       37 + |
       38 + |      observer_dashboard("/observer")
       39 + |    end
    32 40   |  end
    33 41   |end
         ...|
    """)
  end

  test "No Phoenix router found" do
    response =
      test_project()
      |> apply_igniter!()
      |> Igniter.compose_task("observer_web.install")

    assert response.warnings == [
             "No Phoenix router found, Phoenix Liveview is needed for Observer Web\n"
           ]
  end

  test "No dev routes found" do
    assert_raise CaseClauseError, fn ->
      test_project()
      |> Igniter.Project.Module.create_module(TestWeb.Router, """
      use TestWeb, :router

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug :fetch_live_flash
        plug :put_root_layout, {DevWeb.LayoutView, :root}
        plug :protect_from_forgery
        plug :put_secure_browser_headers
      end

      pipeline :api do
        plug :accepts, ["json"]
      end

      scope "/" do
        pipe_through :browser

        live_dashboard "/dashboard", metrics: testWeb.Telemetry
        forward "/mailbox", Plug.Swoosh.MailboxPreview
      end
      """)
      |> apply_igniter!()
      |> Igniter.compose_task("observer_web.install")
    end
  end

  test "Validate info methods" do
    description_text = Docs.long_doc()
    assert description_text =~ "Installs Observer Web into your Phoenix application"

    assert description_text =~
             "This task configures your Phoenix application to use the Observer Web dashboard"

    assert description_text =~ "mix observer_web.install"
  end
end
