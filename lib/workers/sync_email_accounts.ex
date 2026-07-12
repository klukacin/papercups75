defmodule ChatApi.Workers.SyncEmailAccounts do
  @moduledoc """
  Cron fan-out for the generic email channel: enqueues one
  `ChatApi.Workers.SyncEmailAccount` job per *active* email account
  (mirrors `ChatApi.Workers.SyncGmailInboxes`).

  Accounts still inside their failure backoff window are skipped: after a
  failed poll the next attempt is only allowed at
  `last_failed_at + min(2^failure_count, 60) minutes` (capped at one hour —
  see `ChatApi.EmailAccounts.in_backoff?/2`), so a broken mailbox is not
  hammered every minute. A successful poll clears `last_failed_at`, and
  accounts flipped to status `"error"` (10 consecutive failures) are not
  listed at all until a successful "Test connection" resets them.

  Per-account jobs are unique for 55 seconds, so a slow poll cannot pile up
  duplicate jobs for the same account across cron ticks.
  """

  use Oban.Worker, queue: :email_sync

  require Logger

  alias ChatApi.EmailAccounts
  alias ChatApi.EmailAccounts.EmailAccount

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{} = job) do
    Logger.debug("Syncing email accounts: #{inspect(job)}")

    now = DateTime.utc_now()

    EmailAccounts.list_active_email_accounts()
    |> Enum.reject(&EmailAccounts.in_backoff?(&1, now))
    |> Enum.each(fn %EmailAccount{id: email_account_id, account_id: account_id} ->
      %{email_account_id: email_account_id, account_id: account_id}
      |> ChatApi.Workers.SyncEmailAccount.new()
      |> Oban.insert()
    end)

    :ok
  end
end
