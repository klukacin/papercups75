defmodule ChatApiWeb.EmailAccountJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{email_accounts: email_accounts}) do
    %{data: Enum.map(email_accounts, &email_account/1)}
  end

  def show(%{email_account: email_account}) do
    %{data: maybe(email_account, &email_account/1)}
  end

  # NB: passwords must never be exposed through the API — only whether one
  # has been set (`has_imap_password`/`has_smtp_password`).
  def email_account(email_account) do
    %{
      id: email_account.id,
      object: "email_account",
      account_id: email_account.account_id,
      inbox_id: email_account.inbox_id,
      user_id: email_account.user_id,
      from_address: email_account.from_address,
      imap_host: email_account.imap_host,
      imap_port: email_account.imap_port,
      imap_tls: email_account.imap_tls,
      imap_username: email_account.imap_username,
      imap_folder: email_account.imap_folder,
      smtp_host: email_account.smtp_host,
      smtp_port: email_account.smtp_port,
      smtp_tls: email_account.smtp_tls,
      smtp_username: email_account.smtp_username,
      has_imap_password: present?(email_account.imap_password),
      has_smtp_password: present?(email_account.smtp_password),
      status: email_account.status,
      last_error: email_account.last_error,
      last_synced_at: email_account.last_synced_at,
      failure_count: email_account.failure_count,
      settings: email_account.settings,
      metadata: email_account.metadata,
      created_at: email_account.inserted_at,
      updated_at: email_account.updated_at
    }
  end

  defp present?(value), do: is_binary(value) and value != ""
end
