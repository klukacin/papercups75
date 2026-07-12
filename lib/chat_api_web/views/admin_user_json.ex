defmodule ChatApiWeb.AdminUserJSON do
  alias ChatApi.Accounts.{Account, AccountUser}
  alias ChatApi.Users.UserProfile

  def index(%{users: users}) do
    %{data: Enum.map(users, &user/1)}
  end

  # Instance-admin directory entry: unlike `UserJSON.user/1` this includes the
  # user's memberships across ALL workspaces. Only ever rendered for the
  # superadmin-only `GET /api/admin/users` endpoint.
  def user(user) do
    %{
      id: user.id,
      object: "user",
      email: user.email,
      display_name: display_name(user.profile),
      created_at: user.inserted_at,
      disabled_at: user.disabled_at,
      archived_at: user.archived_at,
      is_superadmin: user.is_superadmin,
      memberships: Enum.map(user.account_users, &membership/1)
    }
  end

  defp display_name(%UserProfile{display_name: display_name}), do: display_name
  defp display_name(_profile), do: nil

  defp membership(%AccountUser{} = account_user) do
    %{
      account_id: account_user.account_id,
      company_name: company_name(account_user.account),
      role: account_user.role
    }
  end

  defp company_name(%Account{company_name: company_name}), do: company_name
  defp company_name(_account), do: nil
end
