defmodule ChatApiWeb.GithubAuthorizationJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{github_authorizations: github_authorizations}) do
    %{data: Enum.map(github_authorizations, &github_authorization/1)}
  end

  def show(%{github_authorization: github_authorization}) do
    %{data: maybe(github_authorization, &github_authorization/1)}
  end

  def github_authorization(github_authorization) do
    %{
      id: github_authorization.id,
      created_at: github_authorization.inserted_at,
      updated_at: github_authorization.updated_at,
      token_type: github_authorization.token_type,
      scope: github_authorization.scope,
      github_installation_id: github_authorization.github_installation_id,
      user_id: github_authorization.user_id,
      account_id: github_authorization.account_id
    }
  end
end
