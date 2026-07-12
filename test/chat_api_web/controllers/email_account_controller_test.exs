defmodule ChatApiWeb.EmailAccountControllerTest do
  # async: false because the :verify tests rely on `mock` (mecked modules are global)
  use ChatApiWeb.ConnCase, async: false

  import ChatApi.Factory
  import Mock

  alias ChatApi.EmailAccounts
  alias ChatApi.EmailAccounts.EmailAccount

  @imap_password "super-secret-imap-password"
  @smtp_password "super-secret-smtp-password"

  setup %{conn: conn} do
    account = insert(:account)
    user = insert(:user, account: account)
    inbox = insert(:inbox, account: account)

    email_account =
      insert(:email_account,
        account: account,
        inbox: inbox,
        imap_password: @imap_password,
        smtp_password: @smtp_password
      )

    conn = put_req_header(conn, "accept", "application/json")
    authed_conn = Pow.Plug.assign_current_user(conn, user, [])

    {:ok,
     conn: conn,
     authed_conn: authed_conn,
     account: account,
     user: user,
     inbox: inbox,
     email_account: email_account}
  end

  defp create_params(account, inbox, overrides \\ %{}) do
    :email_account
    |> params_for()
    |> Map.drop([:account_id, :inbox_id, :user_id])
    |> Map.merge(%{
      account_id: account.id,
      inbox_id: inbox.id,
      imap_password: @imap_password,
      smtp_password: @smtp_password
    })
    |> Map.merge(overrides)
  end

  describe "index" do
    test "lists all email accounts for the account", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      resp = get(authed_conn, Routes.email_account_path(authed_conn, :index))
      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [email_account.id]
    end

    test "does not include another account's email accounts", %{authed_conn: authed_conn} do
      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)
      other = insert(:email_account, account: other_account, inbox: other_inbox)

      resp = get(authed_conn, Routes.email_account_path(authed_conn, :index))
      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      refute other.id in ids
    end

    test "never includes passwords in the response", %{authed_conn: authed_conn} do
      resp = get(authed_conn, Routes.email_account_path(authed_conn, :index))

      refute resp.resp_body =~ @imap_password
      refute resp.resp_body =~ @smtp_password
      # the raw password keys must not be rendered (only has_imap_password etc.)
      refute resp.resp_body =~ ~s("imap_password")
      refute resp.resp_body =~ ~s("smtp_password")

      assert [%{"has_imap_password" => true, "has_smtp_password" => true}] =
               json_response(resp, 200)["data"]
    end

    test "returns 401 when unauthenticated", %{conn: conn} do
      resp = get(conn, Routes.email_account_path(conn, :index))

      assert resp.status == 401
    end
  end

  describe "show email_account" do
    test "shows an email account by id", %{
      authed_conn: authed_conn,
      email_account: email_account,
      inbox: inbox,
      account: account
    } do
      resp = get(authed_conn, Routes.email_account_path(authed_conn, :show, email_account.id))

      account_id = account.id
      inbox_id = inbox.id

      assert %{
               "id" => id,
               "object" => "email_account",
               "account_id" => ^account_id,
               "inbox_id" => ^inbox_id,
               "has_imap_password" => true,
               "has_smtp_password" => true
             } = json_response(resp, 200)["data"]

      assert id == email_account.id
      refute resp.resp_body =~ @imap_password
      refute resp.resp_body =~ @smtp_password
    end

    test "renders 404 when asking for another account's email account", %{
      authed_conn: authed_conn
    } do
      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)
      other = insert(:email_account, account: other_account, inbox: other_inbox)

      resp = get(authed_conn, Routes.email_account_path(authed_conn, :show, other.id))

      assert json_response(resp, 404)
    end
  end

  describe "create email_account" do
    test "renders the email account when data is valid", %{
      authed_conn: authed_conn,
      account: account,
      user: user
    } do
      inbox = insert(:inbox, account: account)

      resp =
        post(authed_conn, Routes.email_account_path(authed_conn, :create),
          email_account: create_params(account, inbox, %{from_address: "new@company.test"})
        )

      assert %{"id" => id} = json_response(resp, 201)["data"]
      refute resp.resp_body =~ @imap_password
      refute resp.resp_body =~ @smtp_password

      resp = get(authed_conn, Routes.email_account_path(authed_conn, :show, id))
      account_id = account.id
      inbox_id = inbox.id
      user_id = user.id

      assert %{
               "id" => ^id,
               "object" => "email_account",
               "account_id" => ^account_id,
               "inbox_id" => ^inbox_id,
               "user_id" => ^user_id,
               "from_address" => "new@company.test",
               "has_imap_password" => true,
               "has_smtp_password" => true
             } = json_response(resp, 200)["data"]
    end

    test "forces the account_id to the resolved account", %{
      authed_conn: authed_conn,
      account: account
    } do
      other_account = insert(:account)
      inbox = insert(:inbox, account: account)

      resp =
        post(authed_conn, Routes.email_account_path(authed_conn, :create),
          email_account: create_params(other_account, inbox)
        )

      assert %{"id" => id, "account_id" => account_id} = json_response(resp, 201)["data"]
      assert account_id == account.id
      assert EmailAccounts.get_email_account!(id).account_id == account.id
    end

    test "renders 404 when the inbox belongs to another account", %{
      authed_conn: authed_conn,
      account: account
    } do
      other_inbox = insert(:inbox, account: insert(:account))

      resp =
        post(authed_conn, Routes.email_account_path(authed_conn, :create),
          email_account: create_params(account, other_inbox)
        )

      assert json_response(resp, 404)
    end

    test "renders errors when data is invalid", %{
      authed_conn: authed_conn,
      account: account
    } do
      inbox = insert(:inbox, account: account)

      resp =
        post(authed_conn, Routes.email_account_path(authed_conn, :create),
          email_account: create_params(account, inbox, %{imap_tls: "invalid", imap_host: nil})
        )

      assert json_response(resp, 422)["error"]["errors"] != %{}
    end

    test "returns 401 when unauthenticated", %{conn: conn, account: account, inbox: inbox} do
      resp =
        post(conn, Routes.email_account_path(conn, :create),
          email_account: create_params(account, inbox)
        )

      assert resp.status == 401
    end
  end

  describe "update email_account" do
    test "renders the email account when data is valid", %{
      authed_conn: authed_conn,
      email_account: %EmailAccount{id: id} = email_account
    } do
      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, email_account),
          email_account: %{from_address: "updated@company.test", smtp_port: 465}
        )

      assert %{"id" => ^id} = json_response(resp, 200)["data"]
      refute resp.resp_body =~ @imap_password
      refute resp.resp_body =~ @smtp_password

      resp = get(authed_conn, Routes.email_account_path(authed_conn, :show, id))

      assert %{
               "id" => ^id,
               "from_address" => "updated@company.test",
               "smtp_port" => 465
             } = json_response(resp, 200)["data"]
    end

    test "keeps the stored passwords when password params are blank", %{
      authed_conn: authed_conn,
      email_account: %EmailAccount{id: id} = email_account
    } do
      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, email_account),
          email_account: %{
            imap_password: "",
            smtp_password: "",
            from_address: "keep@company.test"
          }
        )

      assert %{"id" => ^id, "has_imap_password" => true, "has_smtp_password" => true} =
               json_response(resp, 200)["data"]

      updated = EmailAccounts.get_email_account!(id)
      assert updated.imap_password == @imap_password
      assert updated.smtp_password == @smtp_password
    end

    test "replaces the stored password when a non-empty value is given", %{
      authed_conn: authed_conn,
      email_account: %EmailAccount{id: id} = email_account
    } do
      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, email_account),
          email_account: %{imap_password: "brand-new-password"}
        )

      assert json_response(resp, 200)["data"]
      assert EmailAccounts.get_email_account!(id).imap_password == "brand-new-password"
    end

    test "cannot move the email account to another account", %{
      authed_conn: authed_conn,
      account: account,
      email_account: %EmailAccount{id: id} = email_account
    } do
      other_account = insert(:account)

      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, email_account),
          email_account: %{account_id: other_account.id}
        )

      assert json_response(resp, 200)["data"]
      assert EmailAccounts.get_email_account!(id).account_id == account.id
    end

    test "renders 404 when moving to another account's inbox", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      other_inbox = insert(:inbox, account: insert(:account))

      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, email_account),
          email_account: %{inbox_id: other_inbox.id}
        )

      assert json_response(resp, 404)
    end

    test "renders errors when data is invalid", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, email_account),
          email_account: %{imap_port: -1}
        )

      assert json_response(resp, 422)["error"]["errors"] != %{}
    end

    test "renders 404 when updating another account's email account", %{
      authed_conn: authed_conn
    } do
      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)
      other = insert(:email_account, account: other_account, inbox: other_inbox)

      resp =
        put(authed_conn, Routes.email_account_path(authed_conn, :update, other),
          email_account: %{from_address: "hijack@company.test"}
        )

      assert json_response(resp, 404)
    end
  end

  describe "delete email_account" do
    test "deletes the chosen email account", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      resp = delete(authed_conn, Routes.email_account_path(authed_conn, :delete, email_account))

      assert response(resp, 204)

      assert_error_sent(404, fn ->
        get(authed_conn, Routes.email_account_path(authed_conn, :show, email_account))
      end)
    end

    test "renders 404 when deleting another account's email account", %{
      authed_conn: authed_conn
    } do
      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)
      other = insert(:email_account, account: other_account, inbox: other_inbox)

      resp = delete(authed_conn, Routes.email_account_path(authed_conn, :delete, other))

      assert json_response(resp, 404)
    end
  end

  describe "verify email_account" do
    test "verifies a stored email account by id", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn %EmailAccount{} = _account -> {:ok, %{exists: 42}} end,
        verify_smtp: fn %EmailAccount{} = _account -> :ok end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: email_account.id)

        assert %{
                 "imap" => %{"ok" => true, "error" => nil, "exists" => 42},
                 "smtp" => %{"ok" => true, "error" => nil}
               } = json_response(resp, 200)["data"]

        assert_called(ChatApi.EmailAccounts.Client.verify_imap(:_))
        assert_called(ChatApi.EmailAccounts.Client.verify_smtp(:_))
      end
    end

    test "verifies raw credentials before saving", %{authed_conn: authed_conn} do
      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn _params -> {:ok, %{exists: 0}} end,
        verify_smtp: fn _params -> :ok end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify),
            email_account: %{
              from_address: "candidate@company.test",
              imap_host: "imap.company.test",
              imap_username: "candidate",
              imap_password: "candidate-secret",
              smtp_host: "smtp.company.test"
            }
          )

        assert %{
                 "imap" => %{"ok" => true, "exists" => 0},
                 "smtp" => %{"ok" => true}
               } = json_response(resp, 200)["data"]

        refute resp.resp_body =~ "candidate-secret"
      end
    end

    test "reports an IMAP failure without raising", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn _ -> {:error, "IMAP authentication failed"} end,
        verify_smtp: fn _ -> :ok end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: email_account.id)

        assert %{
                 "imap" => %{"ok" => false, "error" => "IMAP authentication failed"},
                 "smtp" => %{"ok" => true, "error" => nil}
               } = json_response(resp, 200)["data"]
      end
    end

    test "reports an SMTP failure without raising", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn _ -> {:ok, %{exists: 1}} end,
        verify_smtp: fn _ -> {:error, "Connection refused"} end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: email_account.id)

        assert %{
                 "imap" => %{"ok" => true, "exists" => 1},
                 "smtp" => %{"ok" => false, "error" => "Connection refused"}
               } = json_response(resp, 200)["data"]
      end
    end

    test "a successful verify on a stored account is the recovery path", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      {:ok, email_account} =
        EmailAccounts.update_email_account(email_account, %{
          status: "error",
          failure_count: 10,
          last_error: "Connection timed out",
          last_failed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn %EmailAccount{} -> {:ok, %{exists: 3}} end,
        verify_smtp: fn %EmailAccount{} -> :ok end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: email_account.id)

        assert %{"imap" => %{"ok" => true}, "smtp" => %{"ok" => true}} =
                 json_response(resp, 200)["data"]
      end

      updated = EmailAccounts.get_email_account!(email_account.id)
      assert updated.status == "active"
      assert updated.failure_count == 0
      assert updated.last_error == nil
      assert updated.last_failed_at == nil
    end

    test "a partially failing verify does not reset the error state", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      {:ok, email_account} =
        EmailAccounts.update_email_account(email_account, %{
          status: "error",
          failure_count: 10,
          last_error: "Connection timed out",
          last_failed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn %EmailAccount{} -> {:ok, %{exists: 3}} end,
        verify_smtp: fn %EmailAccount{} -> {:error, "SMTP authentication failed"} end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: email_account.id)

        assert %{"imap" => %{"ok" => true}, "smtp" => %{"ok" => false}} =
                 json_response(resp, 200)["data"]
      end

      updated = EmailAccounts.get_email_account!(email_account.id)
      assert updated.status == "error"
      assert updated.failure_count == 10
      assert updated.last_error == "Connection timed out"
      assert %DateTime{} = updated.last_failed_at
    end

    test "a successful verify does not re-enable a deliberately disabled account", %{
      authed_conn: authed_conn,
      email_account: email_account
    } do
      {:ok, email_account} =
        EmailAccounts.update_email_account(email_account, %{status: "disabled", failure_count: 2})

      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn %EmailAccount{} -> {:ok, %{exists: 3}} end,
        verify_smtp: fn %EmailAccount{} -> :ok end do
        resp =
          post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: email_account.id)

        assert json_response(resp, 200)["data"]
      end

      updated = EmailAccounts.get_email_account!(email_account.id)
      # Failure bookkeeping is cleared, but the user's explicit disable sticks
      assert updated.status == "disabled"
      assert updated.failure_count == 0
    end

    test "renders 404 when verifying another account's email account", %{
      authed_conn: authed_conn
    } do
      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)
      other = insert(:email_account, account: other_account, inbox: other_inbox)

      with_mock ChatApi.EmailAccounts.Client,
        verify_imap: fn _ -> {:ok, %{exists: 0}} end,
        verify_smtp: fn _ -> :ok end do
        resp = post(authed_conn, Routes.email_account_path(authed_conn, :verify), id: other.id)

        assert json_response(resp, 404)
        refute called(ChatApi.EmailAccounts.Client.verify_imap(:_))
        refute called(ChatApi.EmailAccounts.Client.verify_smtp(:_))
      end
    end

    test "returns 401 when unauthenticated", %{conn: conn, email_account: email_account} do
      resp = post(conn, Routes.email_account_path(conn, :verify), id: email_account.id)

      assert resp.status == 401
    end
  end
end
