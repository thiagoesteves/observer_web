# CHANGELOG (v0.2.X)

## 0.2.8 🚀 (2026-07-21)

### ⚠️ Backwards incompatible changes for 0.2.7
 * None

### Bug fixes
 * [[`PR-68`](https://github.com/thiagoesteves/observer_web/pull/68)] Stop display trace sessions from feeding back on the dashboard itself

### Enhancements
 * [[`PR-64`](https://github.com/thiagoesteves/observer_web/pull/64)] Add Logs pillar with bounded log tails
 * [[`PR-66`](https://github.com/thiagoesteves/observer_web/pull/66)] Add public custom page API
 * [[`PR-63`](https://github.com/thiagoesteves/observer_web/pull/63)] Add OS data via os_mon to the System page
 * [[`PR-67`](https://github.com/thiagoesteves/observer_web/pull/67)] Add read-only JSON API for automation and AI agents
 * [[`PR-69`](https://github.com/thiagoesteves/observer_web/pull/69)] Use Core.disclosure for the Tracing results CONTENT column

## 0.2.7 🚀 (2026-07-14)

### ⚠️ Backwards incompatible changes for 0.2.6
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-61`](https://github.com/thiagoesteves/observer_web/pull/61)] Improvements for the applications process read
 * [[`PR-62`](https://github.com/thiagoesteves/observer_web/pull/62)] Improve version mismatch UX

## 0.2.6 🚀 (2026-07-13)

### ⚠️ Backwards incompatible changes for 0.2.5
 * None

### Bug fixes
 * [[`7f23100`](https://github.com/thiagoesteves/observer_web/commit/7f23100)] Fix NIF socket byte counters and raise page test coverage

### Enhancements
 * [[`PR-50`](https://github.com/thiagoesteves/observer_web/pull/50)] Add Processes pillar with etop-style live ranking
 * [[`PR-51`](https://github.com/thiagoesteves/observer_web/pull/51)] Resolve process labels for unregistered processes in Profiling
 * [[`PR-52`](https://github.com/thiagoesteves/observer_web/pull/52)] Add System pillar and opt-in scheduler utilization metric
 * [[`PR-53`](https://github.com/thiagoesteves/observer_web/pull/53)] Add ETS pillar with gated content previews; System becomes the default page
 * [[`PR-54`](https://github.com/thiagoesteves/observer_web/pull/54)] Add Network pillar with inet throughput and NIF sockets
 * [[`PR-55`](https://github.com/thiagoesteves/observer_web/pull/55)] Add per-application summary table to the Applications page
 * [[`PR-56`](https://github.com/thiagoesteves/observer_web/pull/56)] Responsive header and page controls for smaller monitors
 * [[`f398830`](https://github.com/thiagoesteves/observer_web/commit/f398830)] Shrink navigation properly on smaller monitors
 * [[`PR-57`](https://github.com/thiagoesteves/observer_web/pull/57)] New Supervision Lens logo and browser tab favicon
 * [[`PR-58`](https://github.com/thiagoesteves/observer_web/pull/58)] Add Mnesia option in the ETS feature
 * [[`PR-59`](https://github.com/thiagoesteves/observer_web/pull/59)] Add Crashdump pillar browsing erl_crash.dump files
 * [[`PR-60`](https://github.com/thiagoesteves/observer_web/pull/60)] Update echarts from 5.6.0 to 6.1.0

## 0.2.5 🚀 (2026-07-07)

### ⚠️ Backwards incompatible changes for 0.2.4
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-46`](https://github.com/thiagoesteves/observer_web/pull/46)] Escape names with reserved URL characters in paths
 * [[`PR-47`](https://github.com/thiagoesteves/observer_web/pull/47)] Fix Elixir 1.20 type warnings with Phoenix LiveView 1.2 upgrade
 * [[`PR-48`](https://github.com/thiagoesteves/observer_web/pull/48)] Remove dead :observer_name router option
 * [[`PR-49`](https://github.com/thiagoesteves/observer_web/pull/49)] Add Profiling pillar: Count, Duration, Call Sequence and Flame Graph tools

## 0.2.4 🚀 (2026-05-15)

### ⚠️ Backwards incompatible changes for 0.2.3
 * None

### Bug fixes
 * [[`PR-44`](https://github.com/thiagoesteves/observer_web/pull/44)] observer_web fails when using Cachex/ExHashRing
 * [[`PR-45`](https://github.com/thiagoesteves/observer_web/pull/45)] Updating mix lock due to vulnerabilities

### Enhancements
 * None

## 0.2.3 🚀 (2026-02-27)

### ⚠️ Backwards incompatible changes for 0.2.2
 * None

### Bug fixes
 * [[`ISSUE-42`](https://github.com/thiagoesteves/observer_web/issues/42)] Pattern match error when series_name contains IPv6 address

### Enhancements
 * [[`PR-41`](https://github.com/thiagoesteves/observer_web/pull/41)] Multiples updates and enhancements

## 0.2.2 🚀 (2025-11-10)

### ⚠️ Backwards incompatible changes for 0.2.1
 * None

### Bug fixes
 * None

### Enhancements
 * [[`PR-39`](https://github.com/thiagoesteves/observer_web/pull/39)] Adding configurable option for maximum metric retention period.

## 0.2.1 🚀 (2025-10-27)

### ⚠️ Backwards incompatible changes for 0.2.0
 * None

### Bug fixes
 * None

### Enhancements
 * Removed igniter warnings and added rescue mechanism for process/port monitor

## 0.2.0 (2025-10-27)

### ⚠️ Backwards incompatible changes for 0.1.12

#### Memory Monitoring GenServer
A new GenServer has been added to handle Process and Port memory monitoring, which is utilized by the OTP distribution layer. **All applications must be updated to this version to maintain memory monitoring capabilities.**

#### Configuration Restructuring
The following configuration variables have been moved from module-specific configuration to the root `:observer_web` configuration:

- `data_retention_period`
- `mode`
- `phx_lv_sckt_poller_interval_ms`
- `beam_vm_poller_interval_ms`

**Migration Guide:**

You may not need to update if you are relying on default values.

```elixir
# Before (v0.1.12)
config :observer_web, ObserverWeb.Telemetry,
  mode: :observer,
  data_retention_period: :timer.minutes(30),
  phx_lv_sckt_poller_interval_ms: 5_000,
  beam_vm_poller_interval_ms: 1_000

# After (v0.2.0)
config :observer_web,
  mode: :observer,
  data_retention_period: :timer.minutes(30),
  phx_lv_sckt_poller_interval_ms: 5_000,
  beam_vm_poller_interval_ms: 1_000
```

### Bug fixes
 * None

### Enhancements
 * [[`PR-30`](https://github.com/thiagoesteves/observer_web/pull/30)] Adding configurable timeout for fetching specific states.
 * [[`PR-31`](https://github.com/thiagoesteves/observer_web/pull/31)] Adding process dictionary information.
 * [[`PR-32`](https://github.com/thiagoesteves/observer_web/pull/32)] Adding port/process actions.
 * [[`PR-33`](https://github.com/thiagoesteves/observer_web/pull/33)] Adding port/process memory monitor.
 * [[`PR-34`](https://github.com/thiagoesteves/observer_web/pull/34)] Changing config variable definitions from ObserverWeb.Telemetry to root of observer_web
 * [[`PR-35`](https://github.com/thiagoesteves/observer_web/pull/35)] Adding new version feature that will notify users when observer_web versions don't match across nodes.

# 🚀 Previous Releases
 * [0.1.12 (2025-10-12)](https://github.com/thiagoesteves/observer_web/blob/v0.1.12/CHANGELOG.md)
 * [0.1.11 (2025-08-29)](https://github.com/thiagoesteves/observer_web/blob/v0.1.11/CHANGELOG.md)
 * [0.1.10 (2025-05-26)](https://github.com/thiagoesteves/observer_web/blob/v0.1.10/CHANGELOG.md)
 * [0.1.9 (2025-05-07)](https://github.com/thiagoesteves/observer_web/blob/v0.1.9/CHANGELOG.md)
 * [0.1.8 (2025-04-03)](https://github.com/thiagoesteves/observer_web/blob/v0.1.8/CHANGELOG.md)
 * [0.1.7 (2025-03-21)](https://github.com/thiagoesteves/observer_web/blob/v0.1.7/CHANGELOG.md)
 * [0.1.6 (2025-03-21)](https://github.com/thiagoesteves/observer_web/blob/v0.1.6/CHANGELOG.md)
 * [0.1.5 (2025-02-26)](https://github.com/thiagoesteves/observer_web/blob/v0.1.5/CHANGELOG.md)
 * [0.1.4 (2025-02-11)](https://github.com/thiagoesteves/observer_web/blob/v0.1.4/CHANGELOG.md)
 * [0.1.3 (2025-02-08)](https://github.com/thiagoesteves/observer_web/blob/v0.1.3/CHANGELOG.md)
 * [0.1.2 (2025-02-08)](https://github.com/thiagoesteves/observer_web/blob/v0.1.2/CHANGELOG.md)
 * [0.1.0 (2025-01-06)](https://github.com/thiagoesteves/observer_web/blob/v0.1.0/CHANGELOG.md)