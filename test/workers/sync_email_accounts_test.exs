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
end
