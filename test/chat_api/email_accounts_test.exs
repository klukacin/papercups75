defmodule ChatApi.EmailAccountsTest do
  use ChatApi.DataCase, async: true

  import ChatApi.Factory
  alias ChatApi.EmailAccounts
  alias ChatApi.EmailAccounts.EmailAccount

  setup do
    account = insert(:account)
    inbox = insert(:inbox, account: account)

    email_account =
      insert(:email_account,
        account: account,
        inbox: inbox,
        imap_password: "imap-secret",
        smtp_password: nil
      )

    {:ok, account: account, inbox: inbox, email_account: email_account}
  end

  defp valid_attrs(account, inbox, overrides \\ %{}) do
    :email_account
    |> params_for()
    |> Map.drop([:account_id, :inbox_id, :user_id])
    |> Map.merge(%{account_id: account.id, inbox_id: inbox.id})
    |> Map.merge(overrides)
  end

  describe "list_email_accounts/2" do
    test "returns all email accounts for the given account", %{
      account: account,
      email_account: email_account
    } do
      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)
      _other = insert(:email_account, account: other_account, inbox: other_inbox)

      assert [found] = EmailAccounts.list_email_accounts(account.id)
      assert found.id == email_account.id
    end

    test "supports filtering by inbox_id", %{
      account: account,
      inbox: inbox,
      email_account: email_account
    } do
      another_inbox = insert(:inbox, account: account)
      _another = insert(:email_account, account: account, inbox: another_inbox)

      assert [found] = EmailAccounts.list_email_accounts(account.id, %{"inbox_id" => inbox.id})
      assert found.id == email_account.id
    end
  end

  describe "get_email_account!/1" do
    test "returns the email account with the given id", %{email_account: email_account} do
      assert %EmailAccount{} = found = EmailAccounts.get_email_account!(email_account.id)
      assert found.id == email_account.id
    end

    test "raises if the email account does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        EmailAccounts.get_email_account!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_email_account/1" do
    test "returns nil for an unknown or invalid id", %{email_account: email_account} do
      assert EmailAccounts.get_email_account(Ecto.UUID.generate()) == nil
      assert EmailAccounts.get_email_account("not-a-uuid") == nil
      assert %EmailAccount{} = EmailAccounts.get_email_account(email_account.id)
    end
  end

  describe "find_by_inbox/1" do
    test "returns the email account for the given inbox", %{
      inbox: inbox,
      email_account: email_account
    } do
      assert %EmailAccount{id: id} = EmailAccounts.find_by_inbox(inbox.id)
      assert id == email_account.id
    end

    test "returns nil when the inbox has no email account", %{account: account} do
      inbox = insert(:inbox, account: account)

      assert EmailAccounts.find_by_inbox(inbox.id) == nil
    end
  end

  describe "create_email_account/1" do
    test "creates an email account with valid attrs", %{account: account} do
      inbox = insert(:inbox, account: account)

      attrs =
        valid_attrs(account, inbox, %{
          from_address: "support@company.test",
          imap_host: "imap.company.test"
        })

      assert {:ok, %EmailAccount{} = email_account} = EmailAccounts.create_email_account(attrs)
      assert email_account.from_address == "support@company.test"
      assert email_account.imap_host == "imap.company.test"
      assert email_account.account_id == account.id
      assert email_account.inbox_id == inbox.id
    end

    test "applies defaults for ports, tls, folder and status", %{account: account} do
      inbox = insert(:inbox, account: account)

      attrs = %{
        account_id: account.id,
        inbox_id: inbox.id,
        from_address: "support@company.test",
        imap_host: "imap.company.test",
        imap_username: "support@company.test",
        imap_password: "secret",
        smtp_host: "smtp.company.test"
      }

      assert {:ok, %EmailAccount{} = email_account} = EmailAccounts.create_email_account(attrs)
      assert email_account.imap_port == 993
      assert email_account.imap_tls == "ssl"
      assert email_account.imap_folder == "INBOX"
      assert email_account.smtp_port == 587
      assert email_account.smtp_tls == "starttls"
      assert email_account.status == "active"
      assert email_account.failure_count == 0
    end

    test "requires the mandatory fields" do
      assert {:error, %Ecto.Changeset{} = changeset} = EmailAccounts.create_email_account(%{})

      errors = errors_on(changeset)

      for field <- [
            :from_address,
            :imap_host,
            :imap_username,
            :imap_password,
            :smtp_host,
            :account_id,
            :inbox_id
          ] do
        assert %{^field => ["can't be blank"]} = Map.take(errors, [field])
      end
    end

    test "validates tls values", %{account: account} do
      inbox = insert(:inbox, account: account)

      assert {:error, changeset} =
               account
               |> valid_attrs(inbox, %{imap_tls: "tls-magic"})
               |> EmailAccounts.create_email_account()

      assert %{imap_tls: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} =
               account
               |> valid_attrs(inbox, %{smtp_tls: "no"})
               |> EmailAccounts.create_email_account()

      assert %{smtp_tls: ["is invalid"]} = errors_on(changeset)
    end

    test "validates status values", %{account: account} do
      inbox = insert(:inbox, account: account)

      assert {:error, changeset} =
               account
               |> valid_attrs(inbox, %{status: "sleeping"})
               |> EmailAccounts.create_email_account()

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "validates port ranges", %{account: account} do
      inbox = insert(:inbox, account: account)

      assert {:error, changeset} =
               account
               |> valid_attrs(inbox, %{imap_port: 0})
               |> EmailAccounts.create_email_account()

      assert %{imap_port: [_message]} = errors_on(changeset)

      assert {:error, changeset} =
               account
               |> valid_attrs(inbox, %{smtp_port: 65_536})
               |> EmailAccounts.create_email_account()

      assert %{smtp_port: [_message]} = errors_on(changeset)
    end

    test "validates the from_address format", %{account: account} do
      inbox = insert(:inbox, account: account)

      assert {:error, changeset} =
               account
               |> valid_attrs(inbox, %{from_address: "not-an-email"})
               |> EmailAccounts.create_email_account()

      assert %{from_address: [_message]} = errors_on(changeset)
    end

    test "enforces one email account per inbox", %{account: account, inbox: inbox} do
      assert {:error, changeset} =
               account
               |> valid_attrs(inbox)
               |> EmailAccounts.create_email_account()

      assert %{inbox_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_email_account/2" do
    test "updates the email account with valid attrs", %{email_account: email_account} do
      assert {:ok, %EmailAccount{} = updated} =
               EmailAccounts.update_email_account(email_account, %{
                 from_address: "updated@company.test",
                 imap_host: "imap.updated.test",
                 smtp_port: 465,
                 smtp_tls: "ssl"
               })

      assert updated.from_address == "updated@company.test"
      assert updated.imap_host == "imap.updated.test"
      assert updated.smtp_port == 465
      assert updated.smtp_tls == "ssl"
    end

    test "returns an error changeset with invalid attrs", %{email_account: email_account} do
      assert {:error, %Ecto.Changeset{}} =
               EmailAccounts.update_email_account(email_account, %{imap_host: nil})

      assert EmailAccounts.get_email_account!(email_account.id).imap_host ==
               email_account.imap_host
    end

    test "keeps the stored passwords when password params are blank or absent", %{
      email_account: email_account
    } do
      assert {:ok, updated} =
               EmailAccounts.update_email_account(email_account, %{
                 "imap_password" => "",
                 "from_address" => "updated@company.test"
               })

      assert updated.imap_password == "imap-secret"

      assert {:ok, updated} =
               EmailAccounts.update_email_account(updated, %{imap_password: nil})

      assert updated.imap_password == "imap-secret"

      assert {:ok, updated} =
               EmailAccounts.update_email_account(updated, %{from_address: "another@company.test"})

      assert updated.imap_password == "imap-secret"
    end

    test "replaces the stored password when a non-empty value is given", %{
      email_account: email_account
    } do
      assert {:ok, updated} =
               EmailAccounts.update_email_account(email_account, %{
                 "imap_password" => "new-imap-secret",
                 "smtp_password" => "new-smtp-secret"
               })

      assert updated.imap_password == "new-imap-secret"
      assert updated.smtp_password == "new-smtp-secret"
    end
  end

  describe "delete_email_account/1" do
    test "deletes the email account", %{email_account: email_account} do
      assert {:ok, %EmailAccount{}} = EmailAccounts.delete_email_account(email_account)

      assert_raise Ecto.NoResultsError, fn ->
        EmailAccounts.get_email_account!(email_account.id)
      end
    end
  end

  describe "effective SMTP credentials" do
    test "fall back to the IMAP credentials when blank", %{email_account: email_account} do
      email_account = %EmailAccount{
        email_account
        | imap_username: "imap-user",
          imap_password: "imap-pass",
          smtp_username: nil,
          smtp_password: nil
      }

      assert EmailAccounts.smtp_username(email_account) == "imap-user"
      assert EmailAccounts.smtp_password(email_account) == "imap-pass"

      email_account = %EmailAccount{email_account | smtp_username: "", smtp_password: ""}

      assert EmailAccounts.smtp_username(email_account) == "imap-user"
      assert EmailAccounts.smtp_password(email_account) == "imap-pass"
    end

    test "use the SMTP credentials when present", %{email_account: email_account} do
      email_account = %EmailAccount{
        email_account
        | smtp_username: "smtp-user",
          smtp_password: "smtp-pass"
      }

      assert EmailAccounts.smtp_username(email_account) == "smtp-user"
      assert EmailAccounts.smtp_password(email_account) == "smtp-pass"
    end
  end

  describe "verify_inbox_ownership/2" do
    test "returns :ok when the inbox belongs to the account", %{account: account, inbox: inbox} do
      assert EmailAccounts.verify_inbox_ownership(account.id, inbox.id) == :ok
    end

    test "returns :ok when the inbox_id is nil", %{account: account} do
      assert EmailAccounts.verify_inbox_ownership(account.id, nil) == :ok
    end

    test "returns an error for another account's inbox or an unknown inbox", %{account: account} do
      other_inbox = insert(:inbox, account: insert(:account))

      assert {:error, :not_found, _message} =
               EmailAccounts.verify_inbox_ownership(account.id, other_inbox.id)

      assert {:error, :not_found, _message} =
               EmailAccounts.verify_inbox_ownership(account.id, Ecto.UUID.generate())

      assert {:error, :not_found, _message} =
               EmailAccounts.verify_inbox_ownership(account.id, "not-a-uuid")
    end
  end
end
