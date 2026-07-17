defmodule ChatApiWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :chat_api

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_chat_api_key",
    signing_salt: "QvEKzv2I"
  ]

  socket("/socket", ChatApiWeb.UserSocket,
    websocket: [timeout: 45_000],
    longpoll: false
  )

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :chat_api,
    gzip: true,
    headers: [{"cache-control", "max-age=31536000"}]
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :chat_api)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(Plug.RequestId)
  # Expose Prometheus metrics at /metrics for a self-hosted Grafana stack
  plug(PromEx.Plug, prom_ex_module: ChatApi.PromEx)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Sentry.PlugContext)

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)

  # The embeddable chat widget calls this API cross-origin from arbitrary
  # customer sites, so `origins: "*"` is intentional. Authentication is a Bearer
  # token in the `Authorization` header (never an ambient cookie), so
  # `allow_credentials` must stay FALSE: combining `origins: "*"` with
  # `allow_credentials: true` would let ANY website make cookie/HTTP-auth'd
  # cross-origin requests and read the responses (cross-site data theft). The
  # dashboard is served same-origin and so is unaffected by this.
  plug(Corsica,
    origins: "*",
    allow_credentials: false,
    allow_headers: ["Content-Type", "Authorization", "X-Account-Id"]
  )

  plug(ChatApiWeb.Router)
end
