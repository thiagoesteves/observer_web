# Installation

Observer Web is delivered as a hex package named `observer_web`. The package is entirely self contained—it
doesn't hook into your asset pipeline.

## Prerequisites

1. Ensure [Phoenix Live View][plv] is installed and working in your application. If you don't have
   Live View, follow [these instructions][lvi] to get started.

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

### Usage with Web and Clustering

The Observer Web provides observer ability for the local application as well as any other that is
clustered.

## Customization

Web customization is done through the `Observer.Web.Resolver` behaviour. It allows you to enable
access controls. Using a custom resolver is entirely optional, but you should familiarize yourself
with the default limits and functionality.

Installation is complete and you're all set! Start your Phoenix server and enjoy erlang debugger!!!

[plv]: https://github.com/phoenixframework/phoenix_live_view
[lvi]: https://github.com/phoenixframework/phoenix_live_view#installation
[ac]: Observer.Web.Resolver.html#c:resolve_access/1
[ba]: https://hexdocs.pm/basic_auth/readme.html
[oi]: installation.html
