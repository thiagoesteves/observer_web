defmodule TracingWeb.MixProject do
  use Mix.Project

  @source_url "https://github.com/thiagoesteves/tracing_web"
  @version "0.0.0"

  def project do
    [
      app: :tracing_web,
      version: @version,
      name: "Tracing Web",
      description: "Dashboard for Tracing applications using erlang debugger",
      docs: docs(),
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      package: package(),
      docs: docs(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TracingWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      maintainers: ["Thiago Esteves"],
      licenses: ["MIT"],
      files: ~w(lib priv .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      links: %{
        Website: "https://deployex.pro",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  defp docs do
    [
      main: "overview",
      source_ref: "v#{@version}",
      formatters: ["html"],
      api_reference: false
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:phoenix, "~> 1.7.18"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.0.3"},
      {:phoenix_pubsub, "~> 2.1"},

      # Dev Server
      {:bandit, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.8", only: :dev, runtime: false},
      {:faker, "~> 0.17", only: :dev},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:tailwind, "~> 0.2", only: :dev, runtime: false},

      # Tooling
      {:credo, "~> 1.7", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:floki, "~> 0.33", only: [:test, :dev]},
      {:mox, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},

      # Docs and Publishing
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:makeup_diff, "~> 0.1", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "assets.build": ["tailwind default", "esbuild default"],
      release: [
        "assets.build",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      dev: "run --no-halt dev.exs",
      release: [
        "assets.build",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      # elixir --sname hello -S mix run --no-halt dev.exs
    ]
  end
end
