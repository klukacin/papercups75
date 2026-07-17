defmodule ChatApiWeb.PersonalApiKeyController do
  use ChatApiWeb, :controller

  alias ChatApi.Accounts
  alias ChatApi.ApiKeys
  alias ChatApi.ApiKeys.PersonalApiKey

  action_fallback(ChatApiWeb.FallbackController)

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(
        %{assigns: %{current_user: %{id: user_id}}} = conn,
        _params
      ) do
    account_id = Accounts.get_current_account_id(conn)
    personal_api_keys = ApiKeys.list_personal_api_keys(user_id, account_id)
    render(conn, :index, personal_api_keys: personal_api_keys)
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(%{assigns: %{current_user: %{id: user_id}}} = conn, %{
        "label" => personal_api_key_label
      }) do
    account_id = Accounts.get_current_account_id(conn)

    with {:ok, %PersonalApiKey{} = personal_api_key} <-
           ApiKeys.create_personal_api_key(%{
             label: personal_api_key_label,
             user_id: user_id,
             account_id: account_id,
             value:
               ApiKeys.generate_random_token(personal_api_key_label,
                 user_id: user_id,
                 account_id: account_id
               )
           }) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.personal_api_key_path(conn, :show, personal_api_key))
      |> render(:show, personal_api_key: personal_api_key)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{current_user: %{id: user_id}}} = conn, %{"id" => id}) do
    account_id = Accounts.get_current_account_id(conn)

    case ApiKeys.find_personal_api_key(id, user_id, account_id) do
      %PersonalApiKey{} = personal_api_key -> render(conn, :show, personal_api_key: personal_api_key)
      nil -> {:error, :not_found}
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(%{assigns: %{current_user: %{id: user_id}}} = conn, %{"id" => id}) do
    account_id = Accounts.get_current_account_id(conn)

    with %PersonalApiKey{} = personal_api_key <-
           ApiKeys.find_personal_api_key(id, user_id, account_id),
         {:ok, %PersonalApiKey{}} <- ApiKeys.delete_personal_api_key(personal_api_key) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
