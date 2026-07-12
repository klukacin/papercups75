defmodule ChatApi.SyncEmailAccountTest do
  use ChatApi.DataCase
  use Oban.Testing, repo: ChatApi.Repo

  import ChatApi.Factory
  import Mock

  alias ChatApi.EmailAccounts
  alias ChatApi.EmailAccounts.{Client, Ingestion}
  alias ChatApi.Messages.Message
  alias ChatApi.Workers.SyncEmailAccount

  @fixtures Path.expand("../fixtures/email", __DIR__)

  setup do
    account = insert(:account)
    inbox = insert(:inbox, account: account)

    email_account =
      insert(:email_account,
        account: account,
        inbox: inbox,
        from_address: "support@company.test",
        imap_username: "imap-login@company.test"
      )

    {:ok, account: account, inbox: inbox, email_account: email_account}
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp perform(email_account),
    do: perform_job(SyncEmailAccount, %{"email_account_id" => email_account.id})

  defp reload(email_account), do: EmailAccounts.get_email_account!(email_account.id)

  describe "perform/1" do
    test "processes unseen messages and marks exactly the terminal uids as seen", ctx do
      email_account = ctx.email_account

      {:ok, email_account} =
        EmailAccounts.update_email_account(email_account, %{failure_count: 3})

      messages = [
        # → {:ok, %Message{}}
        %{uid: 11, raw: fixture("simple.eml")},
        # → {:ok, :skipped} (Auto-Submitted)
        %{uid: 12, raw: fixture("auto_submitted.eml")},
        # → {:ok, :duplicate} (same Message-ID as uid 11)
        %{uid: 13, raw: fixture("simple.eml")},
        # → {:error, :parse_failure} — still marked seen so it can't wedge the mailbox
        %{uid: 14, raw: fixture("poison.eml")}
      ]

      test_pid = self()

      with_mock Client,
        fetch_unseen: fn _email_account, _limit -> {:ok, messages} end,
        mark_seen: fn _email_account, uids ->
          send(test_pid, {:mark_seen, uids})
          :ok
        end do
        assert :ok = perform(email_account)

        assert_receive {:mark_seen, [11, 12, 13, 14]}
      end

      # Exactly one message was ingested (skipped/duplicate/poison were not)
      assert [%Message{body: body}] =
               Message |> where(account_id: ^ctx.account.id) |> Repo.all()

      assert body =~ "Hello, I cannot log in to my account"

      # A successful poll records the sync and resets the failure counter
      updated = reload(email_account)
      assert %DateTime{} = updated.last_synced_at
      assert updated.failure_count == 0
      assert updated.last_error == nil
      assert updated.status == "active"
    end

    test "does not mark uids seen when processing fails transiently", ctx do
      messages = [
        %{uid: 21, raw: "ok"},
        %{uid: 22, raw: "transient-error"},
        %{uid: 23, raw: "raises"},
        %{uid: 24, raw: "ok"}
      ]

      test_pid = self()

      with_mocks [
        {Client, [],
         [
           fetch_unseen: fn _email_account, _limit -> {:ok, messages} end,
           mark_seen: fn _email_account, uids ->
             send(test_pid, {:mark_seen, uids})
             :ok
           end
         ]},
        {Ingestion, [],
         [
           process_raw_email: fn
             "ok", _email_account -> {:ok, :skipped}
             "transient-error", _email_account -> {:error, :database_unavailable}
             "raises", _email_account -> raise "database went away mid-poll"
           end
         ]}
      ] do
        assert :ok = perform(ctx.email_account)

        # The transiently failing uids stay unseen and retry on the next poll
        assert_receive {:mark_seen, [21, 24]}
      end

      # The poll itself succeeded, so the sync is still recorded
      assert %DateTime{} = reload(ctx.email_account).last_synced_at
    end

    test "records connect failures: increments failure_count and sets last_error", ctx do
      with_mock Client,
        fetch_unseen: fn _email_account, _limit ->
          {:error, "Connection refused — check host and port"}
        end,
        mark_seen: fn _email_account, _uids -> :ok end do
        assert :ok = perform(ctx.email_account)

        assert_not_called(Client.mark_seen(:_, :_))
      end

      updated = reload(ctx.email_account)
      assert updated.failure_count == 1
      assert updated.last_error == "Connection refused — check host and port"
      assert updated.status == "active"
      assert updated.last_synced_at == nil
    end

    test "the 10th consecutive failure flips the account status to \"error\"", ctx do
      {:ok, email_account} =
        EmailAccounts.update_email_account(ctx.email_account, %{failure_count: 9})

      with_mock Client,
        fetch_unseen: fn _email_account, _limit -> {:error, "Connection timed out"} end do
        assert :ok = perform(email_account)
      end

      updated = reload(email_account)
      assert updated.failure_count == 10
      assert updated.status == "error"
      assert updated.last_error == "Connection timed out"
    end

    test "a successful poll resets a previous failure streak", ctx do
      {:ok, email_account} =
        EmailAccounts.update_email_account(ctx.email_account, %{
          failure_count: 9,
          last_error: "Connection timed out"
        })

      with_mock Client,
        fetch_unseen: fn _email_account, _limit -> {:ok, []} end,
        mark_seen: fn _email_account, _uids -> :ok end do
        assert :ok = perform(email_account)

        # Nothing was processed, so nothing gets flagged
        assert_not_called(Client.mark_seen(:_, :_))
      end

      updated = reload(email_account)
      assert updated.failure_count == 0
      assert updated.last_error == nil
      assert %DateTime{} = updated.last_synced_at
    end

    test "tolerates mark_seen failures (dedup makes reprocessing safe)", ctx do
      with_mock Client,
        fetch_unseen: fn _email_account, _limit ->
          {:ok, [%{uid: 31, raw: fixture("simple.eml")}]}
        end,
        mark_seen: fn _email_account, _uids -> {:error, "Connection closed by server"} end do
        assert :ok = perform(ctx.email_account)
      end

      assert Message |> where(account_id: ^ctx.account.id) |> Repo.aggregate(:count) == 1
      assert %DateTime{} = reload(ctx.email_account).last_synced_at
    end

    test "does not poll accounts that are not active", ctx do
      {:ok, disabled} =
        EmailAccounts.update_email_account(ctx.email_account, %{status: "disabled"})

      with_mock Client,
        fetch_unseen: fn _email_account, _limit -> {:ok, []} end do
        assert :ok = perform(disabled)

        assert_not_called(Client.fetch_unseen(:_, :_))
      end
    end

    test "no-ops for unknown email account ids" do
      with_mock Client,
        fetch_unseen: fn _email_account, _limit -> {:ok, []} end do
        assert :ok =
                 perform_job(SyncEmailAccount, %{
                   "email_account_id" => Ecto.UUID.generate()
                 })

        assert_not_called(Client.fetch_unseen(:_, :_))
      end
    end
  end
end
