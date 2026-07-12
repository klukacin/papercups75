defmodule ChatApiWeb.AdminUserController do
  use ChatApiWeb, :controller

  alias ChatApi.{Accounts, Users}
  alias ChatApi.Users.User

  action_fallback(ChatApiWeb.FallbackController)

  @doc """
  Lists EVERY user on the instance, with their account memberships — the
  instance-admin user directory (`GET /api/admin/users`). Superadmin-only.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    with %User{} = current_user <- conn.assigns.current_user,
         :ok <- require_superadmin(current_user) do
      render(conn, :index, users: Users.list_all_users_with_memberships())
    end
  end

  @spec require_superadmin(User.t()) :: :ok | {:error, :forbidden, String.t()}
  defp require_superadmin(%User{} = user) do
    if Accounts.superadmin?(user) do
      :ok
    else
      {:error, :forbidden, "Only instance admins can access this resource."}
    end
  end
end
