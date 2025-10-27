# CHANGELOG (v0.2.X)

## 0.2.0 (:soon:)

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