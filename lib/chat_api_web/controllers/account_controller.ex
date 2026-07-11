defmodule ChatApiWeb.AccountController do
  use ChatApiWeb, :controller

  alias ChatApi.Accounts
  alias ChatApi.Accounts.Account

  action_fallback ChatApiWeb.FallbackController

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"account" => account_params}) do
    with {:ok, %Account{} = account} <- Accounts.create_account(account_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.account_path(conn, :me))
      |> render(:create, account: account)
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    with current_user when not is_nil(current_user) <- Pow.Plug.current_user(conn) do
      accounts =
        current_user
        |> Accounts.list_accounts_for_user()
        |> Enum.map(fn %Account{id: id} -> Accounts.get_account!(id) end)

      render(conn, :index, accounts: accounts)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    with current_user <- Pow.Plug.current_user(conn),
         %{account_id: id} <- current_user do
      account = Accounts.get_account!(id)
      render(conn, :show, account: account)
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"account" => account_params} = params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         :ok <- verify_path_account(params["id"], account_id),
         :ok <- require_admin(conn, account_id) do
      account = Accounts.get_account!(account_id)

      with {:ok, %Account{} = account} <- Accounts.update_account(account, account_params) do
        render(conn, :show, account: account)
      end
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         :ok <- verify_path_account(params["id"], account_id),
         :ok <- require_admin(conn, account_id) do
      account = Accounts.get_account!(account_id)

      with {:ok, %Account{}} <- Accounts.delete_account(account) do
        send_resp(conn, :no_content, "")
      end
    end
  end

  # These routes are `/api/accounts/:id`, but the operation always targets the
  # RESOLVED account (x-account-id header / primary). Reject a concrete path id
  # that differs from the resolved account so a caller cannot believe they are
  # deleting/renaming the account named in the URL while actually operating on
  # another one. The frontend passes the symbolic id "me".
  @spec verify_path_account(binary() | nil, binary()) :: :ok | {:error, :not_found}
  defp verify_path_account(nil, _account_id), do: :ok
  defp verify_path_account("me", _account_id), do: :ok
  defp verify_path_account(id, account_id) when id == account_id, do: :ok
  defp verify_path_account(_id, _account_id), do: {:error, :not_found}

  # Renaming or deleting the resolved account (which cascades its data) is an
  # admin-only operation. Membership alone is not enough: the current user must
  # be an admin of that specific account (via the `account_users` role).
  @spec require_admin(Plug.Conn.t(), binary()) :: :ok | {:error, :forbidden, binary()}
  defp require_admin(conn, account_id) do
    with %{id: user_id} <- conn.assigns.current_user,
         true <- Accounts.account_admin?(user_id, account_id) do
      :ok
    else
      _ -> {:error, :forbidden, "Must be an admin of this account."}
    end
  end

  @spec me(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def me(conn, _params) do
    case conn.assigns.current_user do
      nil ->
        conn
        |> put_status(401)
        |> json(%{error: %{status: 401, message: "Invalid token"}})

      _current_user ->
        account = Accounts.get_account!(Accounts.get_current_account_id(conn))

        render(conn, :show, account: account)
    end
  end
end
