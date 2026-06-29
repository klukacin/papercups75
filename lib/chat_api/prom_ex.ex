defmodule ChatApi.PromEx do
  @moduledoc """
  PromEx telemetry -> Prometheus exporter.

  Exposes application/BEAM/Phoenix/Ecto/Oban metrics at `/metrics` for a
  self-hosted Prometheus + Grafana stack (replacing the AppSignal SaaS).
  PromEx ships ready-made Grafana dashboards for each plugin below.
  """

  use PromEx, otp_app: :chat_api

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: ChatApiWeb.Router, endpoint: ChatApiWeb.Endpoint},
      Plugins.Ecto,
      Plugins.Oban
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
