defmodule ChatApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat_api,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      # NB: the :phoenix (Phoenix 1.8) and :gettext (gettext 1.0) compilers were
      # removed from their libraries and are no longer required here.
      compilers: Mix.compilers() ++ [:phoenix_swagger],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: [
        papercups: [
          include_executables_for: [:unix],
          applications: [chat_api: :permanent]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ChatApi.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_machina, "~> 2.4", only: [:test]},
      {:mock, "~> 0.3.0", only: :test},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_lambda, "~> 2.0"},
      {:ex_aws_ses, "~> 2.0"},
      {:swoosh, "~> 1.0"},
      {:gen_smtp, "~> 1.0"},
      # override: pow 1.0.39 caps phoenix at < 1.8.0, but it compiles and runs
      # fine on 1.8 (we only use pow's API/plug auth, not its HTML templates),
      # verified by the full test suite. Drop the override once pow ships a
      # release that allows phoenix ~> 1.8.
      {:phoenix, "~> 1.8", override: true},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:tesla, "~> 1.3"},
      {:finch, "~> 0.18"},
      {:jason, "~> 1.0"},
      {:joken, "~> 2.6"},
      {:bandit, "~> 1.0"},
      {:corsica, "~> 2.0"},
      {:pow, "~> 1.0.18"},
      {:oban, "~> 2.17"},
      {:sentry, "~> 13.0"},
      {:google_api_gmail, "~> 0.13"},
      {:oauth2, "~> 2.0"},
      {:mail, "~> 0.2"},
      {:phoenix_swagger, "~> 0.8"},
      {:uuid, "~> 1.1"},
      {:ex_json_schema, "~> 0.5"},
      {:pow_postgres_store, "~> 1.0.0-rc2"},
      {:tz, "~> 0.28"},
      {:scrivener_ecto, "~> 3.1"},
      {:floki, "~> 0.38"},
      {:paginator, "~> 1.0"},
      {:phoenix_pubsub_redis, "~> 3.0"},
      {:prom_ex, "~> 1.12"},
      {:mdex, "~> 0.13"},
      # mdex ships its Rust NIF (mdex_native) as a precompiled binary downloaded
      # from GitHub releases; that is the default and needs no Rust toolchain.
      # rustler is only pulled in as a fallback so the NIF can be built from
      # source in environments that cannot reach GitHub releases (e.g. the
      # Claude Code sandbox, which sets RUSTLER_PRECOMPILED_FORCE_BUILD_ALL in
      # its SessionStart hook). Not used at runtime.
      {:rustler, ">= 0.0.0", optional: true, runtime: false},
      {:html_sanitize_ex, "~> 1.4"},
      {:sweet_xml, "~> 0.7.1"},
      # TODO: just copy code over?
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
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
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
