defmodule ChatApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  def start(_type, _args) do
    pub_sub_opts =
      case redis_url() do
        "rediss://" <> _url ->
          [
            name: ChatApi.PubSub,
            adapter: Phoenix.PubSub.Redis,
            # NB: use redis://localhost:6379 for testing locally
            url: redis_url(),
            node_name: node_name(),
            # Set ssl: true when using `rediss` URLs in Heroku
            ssl: true,
            socket_opts: [verify: :verify_none]
          ]

        "redis://" <> _url ->
          [
            name: ChatApi.PubSub,
            adapter: Phoenix.PubSub.Redis,
            # NB: use redis://localhost:6379 for testing locally
            url: redis_url(),
            node_name: node_name()
          ]

        _ ->
          [name: ChatApi.PubSub]
      end

    Logger.debug("Inspecting PubSub configuration: #{inspect(pub_sub_opts)}")

    # NOTE (sentry 13 upgrade): the old `Sentry.LoggerBackend` Logger backend was
    # replaced by the `Sentry.LoggerHandler` `:logger` handler, which must be
    # attached this way (instead of via `config :logger, backends: ...`). Sentry
    # only actually sends events when a `dsn` is configured, so attaching the
    # handler unconditionally is safe in all environments. The options below
    # preserve the previous behavior: also report warning-level messages and
    # capture `Logger.error/1`-style messages (not just process crashes).
    # Can only be confirmed end-to-end with a live Sentry/GlitchTip DSN.
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        metadata: [:file, :line],
        level: :warning,
        capture_log_messages: true
      }
    })

    children = [
      # Start the Finch HTTP pool (used as the Tesla adapter, replacing hackney)
      {Finch, name: ChatApi.Finch},
      # Start the PromEx telemetry/Prometheus exporter
      ChatApi.PromEx,
      # Start the Ecto repository
      ChatApi.Repo,
      # Start the Telemetry supervisor
      ChatApiWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, pub_sub_opts},
      ChatApiWeb.Presence,
      # Start the Endpoint (http/https)
      ChatApiWeb.Endpoint,
      # Start Oban workers
      {Oban, oban_config()},
      # Automatically delete expired session records
      {Pow.Postgres.Store.AutoDeleteExpired, [interval: :timer.hours(1)]}
      # Start a worker by calling: ChatApi.Worker.start_link(arg)
      # {ChatApi.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChatApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ChatApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Conditionally disable crontab, queues, or plugins here.
  defp oban_config do
    Application.get_env(:chat_api, Oban)
  end

  defp redis_url do
    System.get_env("REDIS_TLS_URL") || System.get_env("REDIS_URL")
  end

  defp node_name do
    # TODO: this might not be reliable (see https://devcenter.heroku.com/articles/dynos#local-environment-variables)
    fallback =
      System.get_env("NODE") || System.get_env("DYNO") ||
        Base.encode16(:crypto.strong_rand_bytes(6))

    case node() do
      nil -> fallback
      :nonode@nohost -> fallback
      n -> n
    end
  end
end
