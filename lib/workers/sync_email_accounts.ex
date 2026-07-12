defmodule ChatApi.Workers.SyncEmailAccounts do
  @moduledoc """
  Cron fan-out for the generic email channel: enqueues one
  `ChatApi.Workers.SyncEmailAccount` job per *active* email account
  (mirrors `ChatApi.Workers.SyncGmailInboxes`).

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

    EmailAccounts.list_active_email_accounts()
    |> Enum.each(fn %EmailAccount{id: email_account_id, account_id: account_id} ->
      %{email_account_id: email_account_id, account_id: account_id}
      |> ChatApi.Workers.SyncEmailAccount.new()
      |> Oban.insert()
    end)

    :ok
  end
end
