# Overview

Observer Web is an easy-to-use tool that integrates into your application to provide observability for processes, ports, and tracing using the [Erlang debugger][edb]. It supports running tracing and observer functionsfor both the local node and any other connected nodes. Powered by [Phoenix LiveView][liv], it is distributed, lightweight, and fully real-time. This library is part of the [DeployEx][dye] project.

[dye]: https://github.com/thiagoesteves/deployex
[edb]: https://www.erlang.org/doc/apps/runtime_tools/dbg.html
[liv]: https://github.com/phoenixframework/phoenix_live_view

## Features

- **🐦‍🔥 Embedded LiveView** - Mount the dashboard directly in your application without any
  external dependencies.

- **🔍 Real Time Tracing** - Trace any function within your application, capturing parameters passed
and also function callers, as many other possibilities.

- **🔬 Process/Port Inspection** - View processes and ports details as well as their status and connectivity (and much more).

## Installation

See the [installation guide](installation.md) for details on installing and configuring Observer Web
for your application.
