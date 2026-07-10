[
  {"lib/observer_web/macros.ex", :unknown_function},
  {"lib/observer_web/monitor/process_port.ex", :pattern_match},
  # :crashdump_viewer (observer app) is invisible to the PLT - Mix prunes undeclared OTP
  # applications from the code path. Every call is behind ObserverWeb.Crashdump.available?/0
  # and exercised against a real crash dump in the test suite.
  {"lib/observer_web/crashdump/server.ex", :unknown_function}
]
