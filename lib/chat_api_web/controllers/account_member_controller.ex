defmodule ChatApiWeb.AccountMemberController do
  use ChatApiWeb, :controller

  alias ChatApi.{Accounts, Users}
  alias ChatApi.Accounts.AccountUser
  alias ChatApi.Users.User

  action_fallback(ChatApiWeb.FallbackController)

  @valid_roles ~w(user admin)

  @doc """
  Adds an EXISTING user (looked up by exact email) as a member of the resolved
  account. Admin-only (based on the caller's `account_users` role for the
  resolved account). Idempotent: adding an existing member is a no-op that
  reports the membership's current role.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"email" => email} = params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         :ok <- require_admin(conn, account_id),
         {:ok, role} <- validate_role(params),
         %User{} = user <- find_user_by_email(email),
         {:ok, _attempted} <- Accounts.create_account_user(account_id, user.id, role),
         # `create_account_user/3` inserts with `on_conflict: :nothing`, so
         # re-fetch to report the EXISTING role when the membership was already
         # there (the requested role must not overwrite it).
         %AccountUser{} = membership <- Accounts.get_account_user(user.id, account_id) do
      json(conn, %{
        data: %{
          account_id: membership.account_id,
          user_id: membership.user_id,
          role: membership.role,
          email: user.email
        }
      })
    end
  end

  def create(_conn, _params),
    do: {:error, :unprocessable_entity, "An email address is required"}

  # Only an admin of the RESOLVED account (`x-account-id` header, falling back
  # to the primary account) may manage its members — same pattern as
  # AccountController.update/delete.
  @spec require_admin(Plug.Conn.t(), binary()) :: :ok | {:error, :forbidden, binary()}
  defp require_admin(conn, account_id) do
    with %User{id: user_id} <- conn.assigns.current_user,
         true <- Accounts.account_admin?(user_id, account_id) do
      :ok
    else
      _ -> {:error, :forbidden, "Must be an admin of this account."}
    end
  end

  @spec validate_role(map()) :: {:ok, String.t()} | {:error, :unprocessable_entity, String.t()}
  defp validate_role(params) do
    case Map.get(params, "role") do
      nil -> {:ok, "user"}
      role when role in @valid_roles -> {:ok, role}
      _ -> {:error, :unprocessable_entity, "Role must be either 'user' or 'admin'"}
    end
  end

  @spec find_user_by_email(binary()) :: User.t() | {:error, :not_found, String.t()}
  defp find_user_by_email(email) do
    case Users.find_user_by_email(email) do
      %User{} = user -> user
      nil -> {:error, :not_found, "No user found with that email"}
    end
  end
end
