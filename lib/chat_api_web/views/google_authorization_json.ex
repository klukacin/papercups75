defmodule ChatApiWeb.GoogleAuthorizationJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{google_authorizations: google_authorizations}) do
    %{data: Enum.map(google_authorizations, &google_authorization/1)}
  end

  def show(%{google_authorization: google_authorization}) do
    %{data: maybe(google_authorization, &google_authorization/1)}
  end

  def google_authorization(google_authorization) do
    %{
      id: google_authorization.id,
      client: google_authorization.client,
      created_at: google_authorization.inserted_at,
      updated_at: google_authorization.updated_at,
      account_id: google_authorization.account_id,
      user_id: google_authorization.user_id,
      scope: google_authorization.scope
    }
  end
end
