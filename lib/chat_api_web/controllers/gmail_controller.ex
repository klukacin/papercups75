defmodule ChatApiWeb.GmailController do
  use ChatApiWeb, :controller

  require Logger

  alias ChatApi.Accounts
  alias ChatApi.Google
  alias ChatApi.Google.GoogleAuthorization

  @spec profile(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def profile(conn, params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %GoogleAuthorization{refresh_token: refresh_token} <-
           Google.get_authorization_by_account(account_id, %{
             client: "gmail",
             type: "support",
             inbox_id:
               params["inbox_id"] || ChatApi.Inboxes.get_account_primary_inbox_id(account_id)
           }) do
      case Google.Gmail.get_profile(refresh_token) do
        {:ok, %{body: %{"emailAddress" => email}}} ->
          json(conn, %{ok: true, data: %{email: email}})

        error ->
          Logger.error("Error retrieving gmail profile: #{inspect(error)}")

          json(conn, %{ok: false, data: nil})
      end
    else
      _ -> {:error, :forbidden, "Authorization required"}
    end
  end

  @spec send(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def send(conn, params) do
    with %{email: email} <- conn.assigns.current_user,
         account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %GoogleAuthorization{refresh_token: refresh_token} <-
           Google.get_authorization_by_account(account_id, %{
             client: "gmail",
             type: "support",
             inbox_id:
               params["inbox_id"] || ChatApi.Inboxes.get_account_primary_inbox_id(account_id)
           }) do
      Google.Gmail.send_message(refresh_token, %{
        to: params["to"] || params["recipient"],
        from: params["from"] || email,
        subject: params["subject"],
        text: params["text"] || params["message"]
      })
      |> case do
        {:ok, %{body: %{"id" => _id}}} = result ->
          json(conn, %{ok: true, data: result})

        error ->
          Logger.error("Error sending email via gmail: #{inspect(error)}")

          json(conn, %{ok: false})
      end
    else
      _ -> {:error, :forbidden, "Authorization required"}
    end
  end
end
