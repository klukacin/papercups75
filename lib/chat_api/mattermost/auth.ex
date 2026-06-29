defmodule ChatApi.Mattermost.Auth do
  use OAuth2.Strategy

  # TODO: allow dynamic Mattermost URL (e.g. pull from `mattermost_authorizations` table)

  def client do
    OAuth2.Client.new(
      strategy: __MODULE__,
      client_id: System.get_env("PAPERCUPS_MATTERMOST_CLIENT_ID"),
      client_secret: System.get_env("PAPERCUPS_MATTERMOST_CLIENT_SECRET"),
      redirect_uri: System.get_env("PAPERCUPS_MATTERMOST_REDIRECT_URI"),
      site: System.get_env("PAPERCUPS_MATTERMOST_URL"),
      authorize_url: "/oauth/authorize",
      token_url: "/oauth/access_token",
      # NOTE (oauth2 2.x upgrade): oauth2 2.x no longer registers a JSON
      # serializer by default, so JSON token responses are not decoded unless we
      # register one. Mattermost's token endpoint returns JSON. Needs live
      # Mattermost OAuth verification.
      serializers: %{"application/json" => Jason}
    )
  end

  def refresh_client() do
    OAuth2.Client.new(
      strategy: OAuth2.Strategy.Refresh,
      client_id: System.get_env("PAPERCUPS_MATTERMOST_CLIENT_ID"),
      client_secret: System.get_env("PAPERCUPS_MATTERMOST_CLIENT_SECRET"),
      site: System.get_env("PAPERCUPS_MATTERMOST_URL"),
      authorize_url: "/oauth/authorize",
      token_url: "/oauth/access_token",
      # NOTE (oauth2 2.x upgrade): see note in `client/0`. Needs live verification.
      serializers: %{"application/json" => Jason}
    )
  end

  def authorize_url!(params \\ []) do
    OAuth2.Client.authorize_url!(client(), params)
  end

  # You can pass options to the underlying http library via `opts` parameter
  def get_token!(params \\ [], headers \\ [], opts \\ []) do
    case params do
      [refresh_token: refresh_token] when not is_nil(refresh_token) ->
        OAuth2.Client.get_token!(refresh_client(), params, headers, opts)

      _ ->
        OAuth2.Client.get_token!(client(), params, headers, opts)
    end
  end

  # Strategy Callbacks
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  # NOTE (oauth2 2.x upgrade): strategy callback signatures are unchanged in 2.x.
  # The actual Mattermost token exchange can only be confirmed with live
  # Mattermost OAuth credentials.
  def get_token(client, params \\ [], headers \\ []) do
    client
    |> put_param(:client_secret, client.client_secret)
    |> put_header("accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
