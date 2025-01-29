[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  export: [
    locals_without_parens: [live_dashboard: 1, live_dashboard: 2]
  ],
  locals_without_parens: [live_dashboard: 1, live_dashboard: 2]
]
