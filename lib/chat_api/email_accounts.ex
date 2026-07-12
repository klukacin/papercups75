defmodule ChatApi.EmailAccounts do
  @moduledoc """
  The EmailAccounts context.

  An `EmailAccount` connects an inbox to a generic email provider via
  IMAP (receiving) and SMTP (sending). Each inbox can have at most one
  email account.
  """

  import Ecto.Query, warn: false

  alias ChatApi.Repo
  alias ChatApi.EmailAccounts.EmailAccount
  alias ChatApi.Inboxes.Inbox

  @spec list_email_accounts(binary(), map()) :: [EmailAccount.t()]
  def list_email_accounts(account_id, filters \\ %{}) do
    EmailAccount
    |> where(account_id: ^account_id)
    |> where(^filter_where(filters))
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists the active email accounts across all workspaces (used by the
  inbound sync cron fan-out).
  """
  @spec list_active_email_accounts() :: [EmailAccount.t()]
  def list_active_email_accounts do
    EmailAccount
    |> where(status: "active")
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @spec get_email_account!(binary()) :: EmailAccount.t()
  def get_email_account!(id), do: Repo.get!(EmailAccount, id)

  @doc """
  Non-raising variant of `get_email_account!/1`; returns `nil` for unknown
  ids as well as for values that are not valid UUIDs.
  """
  @spec get_email_account(binary() | nil) :: EmailAccount.t() | nil
  def get_email_account(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(EmailAccount, uuid)
      :error -> nil
    end
  end

  def get_email_account(_id), do: nil

  @spec find_by_inbox(binary()) :: EmailAccount.t() | nil
  def find_by_inbox(inbox_id) do
    EmailAccount
    |> where(inbox_id: ^inbox_id)
    |> Repo.one()
  end

  @spec create_email_account(map()) :: {:ok, EmailAccount.t()} | {:error, Ecto.Changeset.t()}
  def create_email_account(attrs \\ %{}) do
    %EmailAccount{}
    |> EmailAccount.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_email_account(EmailAccount.t(), map()) ::
          {:ok, EmailAccount.t()} | {:error, Ecto.Changeset.t()}
  def update_email_account(%EmailAccount{} = email_account, attrs) do
    email_account
    |> EmailAccount.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_email_account(EmailAccount.t()) ::
          {:ok, EmailAccount.t()} | {:error, Ecto.Changeset.t()}
  def delete_email_account(%EmailAccount{} = email_account) do
    Repo.delete(email_account)
  end

  @spec change_email_account(EmailAccount.t(), map()) :: Ecto.Changeset.t()
  def change_email_account(%EmailAccount{} = email_account, attrs \\ %{}) do
    EmailAccount.changeset(email_account, attrs)
  end

  # Exponential failure backoff: after a failed poll the next attempt is
  # allowed at `last_failed_at + min(2^failure_count, 60) minutes` (capped at
  # one hour). 1 failure → 2 min, 2 → 4 min, ... 6+ → 60 min.
  @backoff_cap_minutes 60
  # 2^6 = 64 already exceeds the cap, so never exponentiate beyond that
  @backoff_max_exponent 6

  @doc """
  When the account's next poll attempt is allowed, based on the exponential
  failure backoff (see `in_backoff?/2`). Only meaningful when the account has
  a `last_failed_at`.
  """
  @spec backoff_until(EmailAccount.t()) :: DateTime.t()
  def backoff_until(%EmailAccount{last_failed_at: %DateTime{} = last_failed_at} = email_account) do
    exponent = min(email_account.failure_count || 0, @backoff_max_exponent)
    minutes = min(Integer.pow(2, exponent), @backoff_cap_minutes)

    DateTime.add(last_failed_at, minutes * 60, :second)
  end

  @doc """
  Whether the account is still inside its failure backoff window, i.e. the
  sync fan-out should skip it for now. Accounts that never failed (or whose
  last poll succeeded — success clears `last_failed_at`) are never in backoff.
  """
  @spec in_backoff?(EmailAccount.t(), DateTime.t()) :: boolean()
  def in_backoff?(email_account, now \\ DateTime.utc_now())

  def in_backoff?(%EmailAccount{last_failed_at: nil}, _now), do: false

  def in_backoff?(%EmailAccount{} = email_account, %DateTime{} = now),
    do: DateTime.compare(now, backoff_until(email_account)) == :lt

  @doc """
  The effective SMTP username: falls back to the IMAP username when the
  SMTP-specific one is blank.
  """
  @spec smtp_username(EmailAccount.t()) :: String.t() | nil
  def smtp_username(%EmailAccount{smtp_username: value, imap_username: fallback}),
    do: presence(value) || fallback

  @doc """
  The effective SMTP password: falls back to the IMAP password when the
  SMTP-specific one is blank.
  """
  @spec smtp_password(EmailAccount.t()) :: String.t() | nil
  def smtp_password(%EmailAccount{smtp_password: value, imap_password: fallback}),
    do: presence(value) || fallback

  @doc """
  Verifies that the given inbox exists and belongs to the given account.
  `nil` inbox ids are considered fine here (the changeset enforces presence).
  """
  @spec verify_inbox_ownership(binary(), binary() | nil) ::
          :ok | {:error, :not_found, String.t()}
  def verify_inbox_ownership(_account_id, nil), do: :ok

  def verify_inbox_ownership(account_id, inbox_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(inbox_id),
         true <-
           Inbox
           |> where(id: ^inbox_id, account_id: ^account_id)
           |> Repo.exists?() do
      :ok
    else
      _ -> {:error, :not_found, "Inbox not found"}
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp filter_where(params) do
    Enum.reduce(params, dynamic(true), fn
      {"inbox_id", value}, dynamic ->
        dynamic([r], ^dynamic and r.inbox_id == ^value)

      {"status", value}, dynamic ->
        dynamic([r], ^dynamic and r.status == ^value)

      {"from_address", value}, dynamic ->
        dynamic([r], ^dynamic and r.from_address == ^value)

      {_, _}, dynamic ->
        # Not a where parameter
        dynamic
    end)
  end
end
