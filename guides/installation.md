# Installation

Tracing Web is delivered as a hex package named `tracing_web`. The package is entirely self contained—it
doesn't hook into your asset pipeline at all.

## Prerequisites

1. Ensure [Phoenix Live View][plv] is installed and working in your application. If you don't have
   Live View, follow [these instructions][lvi] to get started.

## Configuration

Add `tracing_web` as a dependency for your application. Open `mix.exs` and add the following line:

```elixir
{:tracing_web, "~> 0.1.0"}
```

Now fetch your dependencies:

```bash
mix deps.get
```

This will fetch `tracing_web`.

After fetching the package you'll use the `Tracing.Web.Router` to mount the dashboard within your
application's `router.ex`:

```elixir
# lib/my_app_web/router.ex
use MyAppWeb, :router

import Tracing.Web.Router

...

scope "/" do
  pipe_through :browser

  tracing_dashboard "/tracing"
end
```

Here we're using `"/tracing"` as the mount point, but it can be anywhere you like. See the
`Tracing.Web.Router` docs for additional options.

After you've verified that the dashboard is loading you'll probably want to restrict access to the
dashboard via authentication, either with a [custom resolver's][ac] access controls or [Basic
Auth][ba].

### Usage with Web and Clustering

The Tracing Web provides tracing ability for the local application as well as any other that is
clustered.

## Customization

Web customization is done through the `Tracing.Web.Resolver` behaviour. It allows you to enable
access controls. Using a custom resolver is entirely optional, but you should familiarize yourself
with the default limits and functionality.

Installation is complete and you're all set! Start your Phoenix server and enjoy erlang debugger!!!

[plv]: https://github.com/phoenixframework/phoenix_live_view
[lvi]: https://github.com/phoenixframework/phoenix_live_view#installation
[ac]: Tracing.Web.Resolver.html#c:resolve_access/1
[ba]: https://hexdocs.pm/basic_auth/readme.html
[oi]: installation.html
