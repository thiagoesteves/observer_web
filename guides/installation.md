# Installation

Observer Web is delivered as a hex package named `observer_web`. The package is entirely self contained—it
doesn't hook into your asset pipeline.

## Prerequisites

1. Ensure [Phoenix Live View][plv] is installed and working in your application. If you don't have
   Live View, follow [these instructions][lvi] to get started.

> #### Clustering Required {: .info}
>
> The Observer Web **requires your app to be clustered**. Otherwise, observability will only be 
> available on the current node.

## Configuration

Add `observer_web` as a dependency for your application. Open `mix.exs` and add the following line:

```elixir
{:observer_web, "~> 0.1.0"}
```

Now fetch your dependencies:

```bash
mix deps.get
```

This will fetch `observer_web`.

After fetching the package you'll use the `Observer.Web.Router` to mount the dashboard within your
application's `router.ex`:

```elixir
# lib/my_app_web/router.ex
use MyAppWeb, :router

import Observer.Web.Router

...

scope "/" do
  pipe_through :browser

  observer_dashboard "/observer"
end
```

Here we're using `"/observer"` as the mount point, but it can be anywhere you like. See the
`Observer.Web.Router` docs for additional options.

After you've verified that the dashboard is loading you'll probably want to restrict access to the
dashboard via authentication, either with a [custom resolver's][ac] access controls or [Basic
Auth][ba].

### Retention period for metrics

The Observer Web can monitor Beam VM metrics by default, using ETS tables to store the data.
However, this means that the data is not persisted across restarts. The retention period
for this data can be configured.

By default, without a retention time set, the metrics will only show data received during the
current session. If you'd like to persist this data for a longer period, you can configure
a retention time.

To configure the retention period, use the following optional setting:

```elixir
config :observer_web, ObserverWeb.Telemetry,
  data_retention_period: :timer.minutes(5)
```

### Embedding Observer Web in your app page

In some cases, you may prefer to run the Observer in the same page as your app rather than in 
a separate page. This embedded approach is possible by setting the iframe flag. To implement 
this, your router must add a root path. Here's an example for your application's `router.ex`:

```elixir
# lib/my_app_web/router.ex
use MyAppWeb, :router

import Observer.Web.Router

...

scope "/" do
  pipe_through :browser

  live_session :require_authenticated_user,
    on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}] do
    ...
    live "/embedded-observer", ObserverLive, :index
    ...
  end
  
  observer_dashboard "/observer"
end
```

Next, create an ObserverLive file at `live/observer/index.ex`:

```elixir
defmodule MyAppWeb.ObserverLive do
  @moduledoc """
  """
  use MyAppWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <iframe src={~p"/observer/tracing?iframe=true"} class="min-h-screen" width="100%" height="100%" title="Observer Web">
      </iframe>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Observer Web")
  end
end
```

You can still access the Observer as a separate page by navigating directly to the 
path `/observer"`. However, using the iframe approach allows you to display 
your application's information alongside the Observer in your main page, 
providing a more integrated monitoring experience.

### Usage with Web and Clustering

The Observer Web provides observer ability for the local application as well as any other that is
clustered.

## Customization

Web customization is done through the `Observer.Web.Resolver` behaviour. It allows you to enable
access controls. Using a custom resolver is entirely optional, but you should familiarize yourself
with the default limits and functionality.

Installation is complete and you're all set! Start your Phoenix server and enjoy the observability
via OTP distribution!

[plv]: https://github.com/phoenixframework/phoenix_live_view
[lvi]: https://github.com/phoenixframework/phoenix_live_view#installation
[ac]: Observer.Web.Resolver.html#c:resolve_access/1
[ba]: https://hexdocs.pm/basic_auth/readme.html
[oi]: installation.html
