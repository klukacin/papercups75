defmodule ChatApiWeb.UserController do
  use ChatApiWeb, :controller
  alias ChatApi.Accounts
  alias ChatApi.Users
  alias ChatApi.Users.User
  require Logger

  plug(
    ChatApiWeb.EnsureRolePlug,
    :admin when action in [:disable, :enable, :archive, :set_role]
  )

  action_fallback(ChatApiWeb.FallbackController)

  @spec index(Plug.Conn.t(), map) :: Plug.Conn.t()
  def index(conn, params) do
    users = ChatApi.Users.list_users_by_account(Accounts.get_current_account_id(conn), params)

    render(conn, :index, users: users)
  end

  @spec show(Plug.Conn.t(), map) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    user = ChatApi.Users.get_user_info(Accounts.get_current_account_id(conn), id)

    render(conn, :show, user: user)
  end

  @spec verify_email(Plug.Conn.t(), map) :: Plug.Conn.t()
  def verify_email(conn, %{"token" => token}) do
    case Users.find_by_email_confirmation_token(token) do
      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid verification token"}})

      %{email_confirmed_at: nil} = user ->
        case Users.verify_email(user) do
          {:ok, _user} -> json(conn, %{data: %{success: true}})
          {:error, reason} -> json(conn, %{data: %{success: false, message: reason}})
        end

      _user ->
        json(conn, %{data: %{success: true, message: "Email already verified!"}})
    end
  end

  @spec create_password_reset(Plug.Conn.t(), map) :: Plug.Conn.t()
  def create_password_reset(conn, %{"email" => email}) do
    case Users.find_user_by_email(email) do
      nil ->
        json(conn, %{data: %{ok: true}})

      user ->
        case Users.send_password_reset_email(user) do
          {:ok, result} ->
            Logger.info("Successfully sent password reset email: #{inspect(result)}")

            json(conn, %{data: %{ok: true}})

          {:warning, reason} ->
            Logger.warn("Warning when sending password reset email: #{inspect(reason)}")

            json(conn, %{data: %{ok: true}})

          error ->
            Logger.error("Error sending password reset email: #{inspect(error)}")

            json(conn, %{data: %{ok: false}})
        end
    end
  end

  @spec reset_password(Plug.Conn.t(), map) :: Plug.Conn.t()
  def reset_password(conn, %{"token" => token} = params) do
    case Users.find_by_password_reset_token(token) do
      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid or expired password reset link"}})

      user ->
        case Users.update_password(user, params) do
          {:ok, user} -> json(conn, %{data: %{success: true, email: user.email}})
          {:error, reason} -> json(conn, %{data: %{success: false, message: reason}})
        end
    end
  end

  @spec disable(Plug.Conn.t(), map) :: Plug.Conn.t()
  def disable(conn, %{"id" => user_id}) do
    parsed_id = String.to_integer(user_id)

    case conn.assigns.current_user do
      %{id: ^parsed_id} ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: "You cannot disable yourself."}})

      %{account_id: _account_id} ->
        account_id = Accounts.get_current_account_id(conn)
        {:ok, user} = user_id |> Users.find_by_id(account_id) |> Users.disable_user()

        render(conn, :show, user: user)

      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Not authenticated"}})
    end
  end

  @spec update_role(Plug.Conn.t(), map) :: Plug.Conn.t()
  def update_role(conn, %{"id" => user_id, "role" => "user"}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %User{} = user <- Users.find_by_id(user_id, account_id),
         {:ok, user} <- Users.set_user_role(user) do
      render(conn, :show, user: user)
    end
  end

  def update_role(conn, %{"id" => user_id, "role" => "admin"}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %User{} = user <- Users.find_by_id(user_id, account_id),
         {:ok, user} <- Users.set_admin_role(user) do
      render(conn, :show, user: user)
    end
  end

  def update_role(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: %{status: 400, message: "Role must be either 'user' or 'admin'"}})
  end

  @doc """
  Grants or revokes INSTANCE-superadmin access (`PUT /api/users/:id/superadmin`
  with body `{"is_superadmin": true | false}`). Superadmin-only.

  Guards: a superadmin cannot revoke their own access, and the last superadmin
  on the instance can never be revoked (both 422).
  """
  @spec update_superadmin(Plug.Conn.t(), map) :: Plug.Conn.t()
  def update_superadmin(conn, %{"id" => id} = params) do
    with %User{} = current_user <- conn.assigns.current_user,
         :ok <- require_superadmin(current_user),
         {:ok, is_superadmin} <- validate_is_superadmin_param(params),
         %User{} = user <- find_instance_user(id),
         :ok <- verify_not_self_revocation(current_user, user, is_superadmin),
         {:ok, user} <- apply_superadmin_change(user, is_superadmin) do
      render(conn, :show, user: user)
    end
  end

  @spec require_superadmin(User.t()) :: :ok | {:error, :forbidden, String.t()}
  defp require_superadmin(%User{} = user) do
    if Accounts.superadmin?(user) do
      :ok
    else
      {:error, :forbidden, "Only instance admins can manage instance-admin access."}
    end
  end

  @spec validate_is_superadmin_param(map) ::
          {:ok, boolean()} | {:error, :unprocessable_entity, String.t()}
  defp validate_is_superadmin_param(%{"is_superadmin" => is_superadmin})
       when is_boolean(is_superadmin),
       do: {:ok, is_superadmin}

  defp validate_is_superadmin_param(_params),
    do: {:error, :unprocessable_entity, "is_superadmin must be true or false"}

  # Superadmins manage users across the WHOLE instance, so this lookup is
  # deliberately not account-scoped. Non-numeric ids fail closed as a 404.
  @spec find_instance_user(binary() | integer()) ::
          User.t() | {:error, :not_found, String.t()}
  defp find_instance_user(id) do
    with {user_id, ""} <- Integer.parse(to_string(id)),
         %User{} = user <- ChatApi.Repo.get(User, user_id) do
      user
    else
      _ -> {:error, :not_found, "No user found with that id"}
    end
  end

  @spec verify_not_self_revocation(User.t(), User.t(), boolean()) ::
          :ok | {:error, :unprocessable_entity, String.t()}
  defp verify_not_self_revocation(%User{id: id}, %User{id: id}, false),
    do: {:error, :unprocessable_entity, "You cannot revoke your own instance-admin access."}

  defp verify_not_self_revocation(_current_user, _user, _is_superadmin), do: :ok

  @spec apply_superadmin_change(User.t(), boolean()) ::
          {:ok, User.t()}
          | {:error, :unprocessable_entity, String.t()}
          | {:error, Ecto.Changeset.t()}
  defp apply_superadmin_change(user, is_superadmin) do
    case Users.set_superadmin(user, is_superadmin) do
      {:error, :last_superadmin} ->
        {:error, :unprocessable_entity, "You cannot revoke the last instance admin's access."}

      result ->
        result
    end
  end

  @spec delete(Plug.Conn.t(), map) :: Plug.Conn.t()
  def delete(conn, %{"id" => user_id}) do
    parsed_id = String.to_integer(user_id)

    case conn.assigns.current_user do
      %{id: ^parsed_id, account_id: account_id} ->
        {:ok, _user} = user_id |> Users.find_by_id(account_id) |> Users.delete_user()

        json(conn, %{data: %{ok: true}})

      # TODO: should we support an admin user deleting a non-admin user on the same account?
      %{id: _id} ->
        conn
        |> put_status(403)
        |> json(%{error: %{status: 403, message: "You cannot delete another user."}})

      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Not authenticated"}})
    end
  end

  @spec archive(Plug.Conn.t(), map) :: Plug.Conn.t()
  def archive(conn, %{"id" => user_id}) do
    parsed_id = String.to_integer(user_id)

    case conn.assigns.current_user do
      %{id: ^parsed_id} ->
        conn
        |> put_status(403)
        |> json(%{error: %{status: 403, message: "You cannot archive yourself."}})

      %{id: _id} ->
        account_id = Accounts.get_current_account_id(conn)
        {:ok, user} = user_id |> Users.find_by_id(account_id) |> Users.archive_user()

        render(conn, :show, user: user)

      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Not authenticated"}})
    end
  end

  @spec enable(Plug.Conn.t(), map) :: Plug.Conn.t()
  def enable(conn, %{"id" => user_id}) do
    parsed_id = String.to_integer(user_id)

    case conn.assigns.current_user do
      %{id: ^parsed_id} ->
        conn
        |> put_status(400)
        |> json(%{error: %{status: 400, message: "You cannot enable yourself."}})

      %{account_id: _account_id} ->
        account_id = Accounts.get_current_account_id(conn)
        {:ok, user} = user_id |> Users.find_by_id(account_id) |> Users.enable_user()

        render(conn, :show, user: user)

      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Not authenticated"}})
    end
  end
end
