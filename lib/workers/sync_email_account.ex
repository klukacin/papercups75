defmodule ChatApi.Workers.SyncEmailAccount do
  @moduledoc """
  Polls one email account's IMAP folder for unseen messages and runs each
  through `ChatApi.EmailAccounts.Ingestion`.

  ## At-least-once semantics

  A message is only marked `\\Seen` once processing reached a *terminal*
  state: created (`{:ok, %Message{}}`), skipped, duplicate, or a parse
  failure (poison messages must not wedge the mailbox). Messages that fail
  transiently (e.g. the database is briefly unavailable) stay unseen and
  are retried on the next poll — `Ingestion`'s Message-ID dedup makes that
  reprocessing safe.

  ## Failure bookkeeping

  A successful poll updates `last_synced_at` and resets
  `failure_count`/`last_error`/`last_failed_at`; a failed connect/fetch —
  or a failed `mark_seen` (see below) — increments `failure_count` and
  records `last_error` + `last_failed_at`. The fan-out
  (`ChatApi.Workers.SyncEmailAccounts`) uses `last_failed_at`/`failure_count`
  for exponential backoff, and after 10 consecutive failures the account's
  status is flipped to `"error"` so it stops being polled until a successful
  "Test connection" (the verify endpoint) resets it.

  A `mark_seen` failure counts as a poll failure on purpose: when messages
  cannot be flagged `\\Seen` they are re-fetched and re-processed on every
  poll, and only the Message-ID dedup prevents duplicates — that state must
  surface (and back off) instead of silently looping.
  """

  use Oban.Worker, queue: :email_sync, unique: [period: 55], max_attempts: 1

  require Logger

  alias ChatApi.EmailAccounts
  alias ChatApi.EmailAccounts.{Client, EmailAccount, Ingestion}

  @fetch_limit 50
  @max_failures_before_error 10

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"email_account_id" => email_account_id}} = job) do
    Logger.debug("Syncing email account #{email_account_id}: #{inspect(job)}")

    case EmailAccounts.get_email_account(email_account_id) do
      %EmailAccount{status: "active"} = email_account -> sync(email_account)
      _disabled_or_missing -> :ok
    end
  end

  @spec sync(EmailAccount.t()) :: :ok
  def sync(%EmailAccount{} = email_account) do
    with {:ok, messages} <- Client.fetch_unseen(email_account, @fetch_limit),
         :ok <-
           messages
           |> process_messages(email_account)
           |> mark_processed_seen(email_account) do
      record_success(email_account)
    else
      {:error, reason} -> record_failure(email_account, reason)
    end

    :ok
  end

  # Returns the uids that reached a terminal state and can be marked seen.
  defp process_messages(messages, %EmailAccount{} = email_account) do
    messages
    |> Enum.reduce([], fn %{uid: uid, raw: raw}, seen_uids ->
      case safe_process_raw_email(raw, email_account) do
        {:ok, _message_or_skip_reason} ->
          [uid | seen_uids]

        {:error, :parse_failure} ->
          # Poison message: it will never parse, so mark it seen anyway —
          # otherwise it would wedge the mailbox forever.
          [uid | seen_uids]

        {:error, reason} ->
          Logger.error(
            "[SyncEmailAccount] Transient failure processing message #{uid} for " <>
              "email account #{email_account.id} (will retry next poll): #{inspect(reason)}"
          )

          seen_uids
      end
    end)
    |> Enum.reverse()
  end

  # Ingestion returns error tuples for expected failures; anything raised
  # (e.g. the database going away mid-poll) is treated as transient so the
  # message stays unseen and is retried on the next poll.
  defp safe_process_raw_email(raw, %EmailAccount{} = email_account) do
    Ingestion.process_raw_email(raw, email_account)
  rescue
    error -> {:error, error}
  end

  defp mark_processed_seen([], _email_account), do: :ok

  defp mark_processed_seen(uids, %EmailAccount{} = email_account) do
    case Client.mark_seen(email_account, uids) do
      :ok ->
        :ok

      {:error, reason} = error ->
        # Already-ingested messages are deduplicated by Message-ID on the
        # next poll, so failing to flag them is safe for correctness — but
        # it means the same mail is re-fetched every poll, so it counts as
        # a poll failure (backoff + last_error) instead of being swallowed.
        Logger.warning(
          "[SyncEmailAccount] Could not mark messages #{inspect(uids)} as seen for " <>
            "email account #{email_account.id}: #{inspect(reason)}"
        )

        error
    end
  end

  defp record_success(%EmailAccount{} = email_account) do
    {:ok, _email_account} =
      EmailAccounts.update_email_account(email_account, %{
        last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
        failure_count: 0,
        last_error: nil,
        last_failed_at: nil
      })

    :ok
  end

  defp record_failure(%EmailAccount{} = email_account, reason) do
    failure_count = (email_account.failure_count || 0) + 1

    Logger.error(
      "[SyncEmailAccount] Failed to sync email account #{email_account.id} " <>
        "(failure ##{failure_count}): #{inspect(reason)}"
    )

    attrs = %{
      failure_count: failure_count,
      last_error: format_error(reason),
      last_failed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    attrs =
      if failure_count >= @max_failures_before_error do
        Map.put(attrs, :status, "error")
      else
        attrs
      end

    {:ok, _email_account} = EmailAccounts.update_email_account(email_account, attrs)

    :ok
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
