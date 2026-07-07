# Overview

Observer Web is an easy-to-use tool that integrates into your application, providing 
enhanced observability. Leveraging OTP distribution, it offers tracing and profiling 
through the [Erlang debugger][edb], along with detailed insights into process/port 
statuses and Beam VM statistics.

Powered by [Phoenix LiveView][liv], it is distributed, lightweight, fully real-time and __safe to use in production__. This
library is part of the [DeployEx][dye] project.

[dye]: https://github.com/thiagoesteves/deployex
[edb]: https://www.erlang.org/doc/apps/runtime_tools/dbg.html
[liv]: https://github.com/phoenixframework/phoenix_live_view

## Features

- **🐦‍🔥 Embedded LiveView** - Mount the dashboard directly in your application without any
external dependencies.

![Liveview](./static/liveview.png)

- **🔍 Real Time Tracing** - Trace any function within your application, capturing parameters passed
and also function callers, as many other possibilities.

![Observer Tracing Dashboard](./static/tracing_dash.png)

- **🔥 Function Profiling** - Aggregate traced calls into a report instead of a live stream:
call counts, durations (sum, average, min, max or a distribution histogram), per-process
call sequence trees and flame graphs, all with the same production-safe limits as tracing.

![Observer Profiling Dashboard](./static/profiling_dash.png)

- **🔬 Process/Port Inspection** - View processes and ports details as well as their status and 
connectivity (and much more).

![Observer Application Dashboard](./static/applications_tree.png)

- **📊 Realtime VM Metrics** - Powered by ets table and OTP 
distribution, vm memory statistics are stored and easily filtered.

![Observer Metrics Dashboard](./static/metrics_dash.png)

- **🖼️ Embedded Mode** - Observer Web can be run using iframes, seamlessly integrating the 
observability experience within your application.

## Installation

See the [installation guide](installation.md) for details on installing and configuring Observer Web
for your application.
