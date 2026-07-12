defmodule ChatApi.SyncEmailAccountsTest do
  use ChatApi.DataCase
  use Oban.Testing, repo: ChatApi.Repo

  import ChatApi.Factory

  alias ChatApi.Workers.{SyncEmailAccount, SyncEmailAccounts}

  defp insert_email_account(attrs) do
    account = insert(:account)
    inbox = insert(:inbox, account: account)

    insert(:email_account, Keyword.merge([account: account, inbox: inbox], attrs))
  end

  defp minutes_ago(minutes) do
    DateTime.utc_now()
    |> DateTime.add(-minutes * 60, :second)
    |> DateTime.truncate(:second)
  end

  describe "perform/1" do
    test "enqueues one sync job per active email account (and only for active ones)" do
      active_one = insert_email_account(status: "active")
      active_two = insert_email_account(status: "active")
      disabled = insert_email_account(status: "disabled")
      errored = insert_email_account(status: "error")

      assert :ok = perform_job(SyncEmailAccounts, %{})

      assert_enqueued(
        worker: SyncEmailAccount,
        args: %{
          email_account_id: active_one.id,
          account_id: active_one.account_id
        }
      )

      assert_enqueued(
        worker: SyncEmailAccount,
        args: %{
          email_account_id: active_two.id,
          account_id: active_two.account_id
        }
      )

      refute_enqueued(worker: SyncEmailAccount, args: %{email_account_id: disabled.id})
      refute_enqueued(worker: SyncEmailAccount, args: %{email_account_id: errored.id})
    end

    test "per-account jobs are unique within the polling period" do
      email_account = insert_email_account(status: "active")

      assert :ok = perform_job(SyncEmailAccounts, %{})
      assert :ok = perform_job(SyncEmailAccounts, %{})

      jobs = all_enqueued(worker: SyncEmailAccount)

      assert [%Oban.Job{args: %{"email_account_id" => enqueued_id}}] = jobs
      assert enqueued_id == email_account.id
    end
  end

  describe "perform/1 — failure backoff" do
    test "skips accounts inside their backoff window and includes ones outside it" do
      # failure_count 2 → next attempt allowed 2^2 = 4 minutes after the failure
      in_backoff =
        insert_email_account(status: "active", failure_count: 2, last_failed_at: minutes_ago(3))

      due =
        insert_email_account(status: "active", failure_count: 2, last_failed_at: minutes_ago(5))

      never_failed = insert_email_account(status: "active")

      assert :ok = perform_job(SyncEmailAccounts, %{})

      refute_enqueued(worker: SyncEmailAccount, args: %{email_account_id: in_backoff.id})
      assert_enqueued(worker: SyncEmailAccount, args: %{email_account_id: due.id})
      assert_enqueued(worker: SyncEmailAccount, args: %{email_account_id: never_failed.id})
    end

    test "caps the backoff window at 60 minutes" do
      # failure_count 9 → 2^9 = 512 minutes uncapped; the cap keeps it at 60
      in_backoff =
        insert_email_account(status: "active", failure_count: 9, last_failed_at: minutes_ago(59))

      due =
        insert_email_account(status: "active", failure_count: 9, last_failed_at: minutes_ago(61))

      assert :ok = perform_job(SyncEmailAccounts, %{})

      refute_enqueued(worker: SyncEmailAccount, args: %{email_account_id: in_backoff.id})
      assert_enqueued(worker: SyncEmailAccount, args: %{email_account_id: due.id})
    end
  end
end
