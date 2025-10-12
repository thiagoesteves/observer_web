defmodule ObserverWeb.MixProject do
  use Mix.Project

  @source_url "https://github.com/thiagoesteves/observer_web"
  @version "0.1.12"

  def project do
    [
      app: :observer_web,
      version: @version,
      name: "Observer Web",
      description: "Observer Web Dashboard for OTP management and performance metrics",
      docs: docs(),
      extra_section: "GUIDES",
      extras: extras(),
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      package: package(),
      docs: docs(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        check_plt: true,
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
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
      mod: {ObserverWeb.Application, []},
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
      files: ~w(lib priv/static/* .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
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
      source_url: @source_url,
      formatters: ["html"],
      api_reference: false,
      extra_section: "GUIDES",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp extras do
    [
      "guides/overview.md",
      "guides/installation.md",
      "CHANGELOG.md": [filename: "changelog", title: "Changelog"]
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Advanced: ~r/guides\/advanced\/.?/
    ]
  end

  defp copy_ex_doc(_) do
    static_destination_path = "./doc/static"
    File.mkdir_p!(static_destination_path)

    File.cp_r("./guides/static", static_destination_path, fn _source, _destination ->
      true
    end)
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 3.3 or ~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},

      # Dev Server
      {:bandit, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.8", only: :dev, runtime: false},
      {:faker, "~> 0.17", only: :dev},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:tailwind, "~> 0.4", only: :dev, runtime: false},

      # Telemetry
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Tooling
      {:credo, "~> 1.7", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:floki, "~> 0.33", only: [:test, :dev]},
      {:mox, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:igniter, "~> 0.5", only: [:dev, :test]},

      # Docs and Publishing
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
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
      docs: ["docs", &copy_ex_doc/1],
      "assets.build": ["tailwind default", "esbuild default"],
      release: [
        "assets.build",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      "test.ci": [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "deps.audit",
        "sobelow --exit --threshold medium --skip -i Config.HTTPS",
        "test --raise"
      ]
    ]
  end
end
