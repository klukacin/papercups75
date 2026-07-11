defmodule ChatApiWeb.WorkspaceController do
  use ChatApiWeb, :controller

  alias ChatApi.{Accounts, Inboxes, Repo}
  alias ChatApi.Accounts.Account
  alias ChatApi.Users.User

  action_fallback(ChatApiWeb.FallbackController)

  @doc """
  Creates a NEW workspace (account) with the current user as an admin member.

  Mirrors the account-creation half of registration: the account gets the
  default subscription plan and a primary inbox (with the creator as an inbox
  member). The user's primary account (`users.account_id`) is NOT changed —
  the new workspace is reachable via the `x-account-id` header.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with %User{} = user <- conn.assigns.current_user,
         {:ok, %{account: %Account{id: account_id}}} <-
           user
           |> create_workspace_transaction(params)
           |> Repo.transaction() do
      conn
      |> put_status(:created)
      |> put_view(json: ChatApiWeb.AccountJSON)
      # Reuse the same account JSON shape as `GET /api/accounts`
      |> render(:show, account: Accounts.get_account!(account_id))
    else
      {:error, _operation, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      error -> error
    end
  end

  @spec create_workspace_transaction(User.t(), map()) :: Ecto.Multi.t()
  defp create_workspace_transaction(%User{} = user, params) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:account, fn _repo, %{} ->
      case Accounts.create_account(%{company_name: params["company_name"]}) do
        {:ok, account} ->
          Accounts.update_billing_info(account, %{
            subscription_plan: default_subscription_plan()
          })

        error ->
          error
      end
    end)
    |> Ecto.Multi.run(:membership, fn _repo, %{account: account} ->
      # The creator administers the workspace they created.
      Accounts.create_account_user(account.id, user.id, "admin")
    end)
    |> Ecto.Multi.run(:inbox, fn _repo, %{account: account} ->
      Inboxes.create_inbox(%{
        account_id: account.id,
        name: "Primary Inbox",
        description:
          "This is the primary Papercups inbox for #{account.company_name}. All messages will flow into here by default.",
        is_primary: true,
        is_private: false
      })
    end)
    |> Ecto.Multi.run(:inbox_member, fn _repo, %{account: account, inbox: inbox} ->
      Inboxes.create_inbox_member(%{
        inbox_id: inbox.id,
        account_id: account.id,
        user_id: user.id,
        role: "admin"
      })
    end)
  end

  # Same default as RegistrationController: self-hosted instances get the
  # unrestricted "team" plan; the hosted app starts accounts on "starter".
  @spec default_subscription_plan() :: String.t()
  defp default_subscription_plan() do
    case System.get_env("BACKEND_URL", "") do
      "app.papercups.io" -> "starter"
      _ -> "team"
    end
  end
end
