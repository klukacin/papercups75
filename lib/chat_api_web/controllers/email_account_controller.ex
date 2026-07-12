defmodule ChatApiWeb.EmailAccountController do
  use ChatApiWeb, :controller

  alias ChatApi.{Accounts, EmailAccounts}
  alias ChatApi.EmailAccounts.EmailAccount

  action_fallback(ChatApiWeb.FallbackController)

  plug(:authorize when action in [:show, :update, :delete])

  defp authorize(conn, _) do
    id = conn.path_params["id"]

    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %EmailAccount{account_id: ^account_id} = email_account <-
           EmailAccounts.get_email_account!(id) do
      assign(conn, :current_email_account, email_account)
    else
      _ -> ChatApiWeb.FallbackController.call(conn, {:error, :not_found}) |> halt()
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn) do
      email_accounts = EmailAccounts.list_email_accounts(account_id, params)
      render(conn, :index, email_accounts: email_accounts)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"email_account" => email_account_params}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         :ok <-
           EmailAccounts.verify_inbox_ownership(account_id, email_account_params["inbox_id"]),
         {:ok, %EmailAccount{} = email_account} <-
           email_account_params
           |> Map.merge(%{
             "account_id" => account_id,
             "user_id" => conn.assigns.current_user.id
           })
           |> EmailAccounts.create_email_account() do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.email_account_path(conn, :show, email_account)
      )
      |> render(:show, email_account: email_account)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => _id}) do
    render(conn, :show, email_account: conn.assigns.current_email_account)
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => _id, "email_account" => email_account_params}) do
    email_account = conn.assigns.current_email_account
    # The account is fixed at creation time and the creator is not editable.
    params = Map.drop(email_account_params, ["account_id", "user_id"])

    with :ok <-
           EmailAccounts.verify_inbox_ownership(
             email_account.account_id,
             Map.get(params, "inbox_id", email_account.inbox_id)
           ),
         {:ok, %EmailAccount{} = email_account} <-
           EmailAccounts.update_email_account(email_account, params) do
      render(conn, :show, email_account: email_account)
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => _id}) do
    with {:ok, %EmailAccount{}} <-
           EmailAccounts.delete_email_account(conn.assigns.current_email_account) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Verifies IMAP/SMTP connectivity for either a stored email account
  (`{"id": ...}`) or a not-yet-saved credentials map. Runs both checks and
  always renders a result — it never raises for connection-level failures.
  """
  @spec verify(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def verify(conn, params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         {:ok, config} <- resolve_verify_config(params, account_id) do
      imap =
        case EmailAccounts.Client.verify_imap(config) do
          {:ok, %{exists: exists}} -> %{ok: true, error: nil, exists: exists}
          {:error, reason} -> %{ok: false, error: reason, exists: nil}
        end

      smtp =
        case EmailAccounts.Client.verify_smtp(config) do
          :ok -> %{ok: true, error: nil}
          {:error, reason} -> %{ok: false, error: reason}
        end

      json(conn, %{data: %{imap: imap, smtp: smtp}})
    end
  end

  defp resolve_verify_config(%{"id" => id}, account_id) when is_binary(id) and id != "" do
    case EmailAccounts.get_email_account(id) do
      %EmailAccount{account_id: ^account_id} = email_account -> {:ok, email_account}
      _ -> {:error, :not_found}
    end
  end

  defp resolve_verify_config(%{"email_account" => %{} = params}, _account_id),
    do: {:ok, params}

  defp resolve_verify_config(%{} = params, _account_id), do: {:ok, params}
end
