defmodule ChatApiWeb.AccountMemberController do
  use ChatApiWeb, :controller

  alias ChatApi.{Accounts, Repo, Users}
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

  @doc """
  Updates the STORED membership role (`account_users.role`) of a member of the
  resolved account (`PUT /api/account_members/:user_id` with body
  `{"role": "user" | "admin"}`).

  The caller must administer the resolved account (`Accounts.account_admin?/2`,
  so instance superadmins qualify in any workspace). The last remaining admin
  of a workspace cannot be demoted — this applies to superadmin callers too,
  since their bypass never changes stored roles.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"user_id" => user_id} = params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         :ok <- require_admin(conn, account_id),
         {:ok, role} <- validate_role_param(params),
         %AccountUser{} = membership <- find_membership(user_id, account_id),
         :ok <- verify_not_last_admin_demotion(membership, role),
         {:ok, membership} <- Accounts.update_account_user_role(membership, role) do
      json(conn, %{
        data: %{
          account_id: membership.account_id,
          user_id: membership.user_id,
          role: membership.role,
          email: membership.user.email
        }
      })
    end
  end

  @doc """
  Removes a member from the resolved account (`DELETE /api/account_members/:user_id`),
  deleting only the `account_users` membership row — never the user.

  Admin-of-resolved-account only (superadmins qualify). A user can never be
  removed from their PRIMARY workspace (`users.account_id`), and the last
  admin membership of a workspace cannot be removed.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"user_id" => user_id}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         :ok <- require_admin(conn, account_id),
         %AccountUser{} = membership <- find_membership(user_id, account_id),
         :ok <- verify_not_primary_workspace(membership),
         :ok <- verify_not_last_admin_removal(membership),
         {:ok, _membership} <- Accounts.delete_account_user(membership) do
      send_resp(conn, :no_content, "")
    end
  end

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

  # Unlike `create/2` (which defaults a missing role to "user"), updating an
  # existing membership requires an explicit, valid role.
  @spec validate_role_param(map()) ::
          {:ok, String.t()} | {:error, :unprocessable_entity, String.t()}
  defp validate_role_param(%{"role" => role}) when role in @valid_roles, do: {:ok, role}

  defp validate_role_param(_params),
    do: {:error, :unprocessable_entity, "Role must be either 'user' or 'admin'"}

  # The REAL stored membership (`Accounts.get_account_user/2` has no superadmin
  # override), with the user preloaded for the primary-workspace guard and the
  # response email. Non-numeric ids fail closed as a 404.
  @spec find_membership(binary() | integer(), binary()) ::
          AccountUser.t() | {:error, :not_found, String.t()}
  defp find_membership(user_id, account_id) do
    with {parsed_user_id, ""} <- Integer.parse(to_string(user_id)),
         %AccountUser{} = membership <- Accounts.get_account_user(parsed_user_id, account_id) do
      Repo.preload(membership, :user)
    else
      _ -> {:error, :not_found, "That user is not a member of this account"}
    end
  end

  @spec verify_not_last_admin_demotion(AccountUser.t(), String.t()) ::
          :ok | {:error, :unprocessable_entity, String.t()}
  defp verify_not_last_admin_demotion(%AccountUser{role: "admin"} = membership, "user") do
    if Accounts.count_account_admins(membership.account_id) <= 1 do
      {:error, :unprocessable_entity, "Cannot demote the last admin of this workspace."}
    else
      :ok
    end
  end

  defp verify_not_last_admin_demotion(_membership, _role), do: :ok

  @spec verify_not_primary_workspace(AccountUser.t()) ::
          :ok | {:error, :unprocessable_entity, String.t()}
  defp verify_not_primary_workspace(%AccountUser{
         account_id: account_id,
         user: %User{account_id: primary_account_id}
       })
       when account_id == primary_account_id,
       do: {:error, :unprocessable_entity, "Cannot remove a member from their primary workspace."}

  defp verify_not_primary_workspace(_membership), do: :ok

  @spec verify_not_last_admin_removal(AccountUser.t()) ::
          :ok | {:error, :unprocessable_entity, String.t()}
  defp verify_not_last_admin_removal(%AccountUser{role: "admin"} = membership) do
    if Accounts.count_account_admins(membership.account_id) <= 1 do
      {:error, :unprocessable_entity, "Cannot remove the last admin of this workspace."}
    else
      :ok
    end
  end

  defp verify_not_last_admin_removal(_membership), do: :ok
end
