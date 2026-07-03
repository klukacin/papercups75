defmodule ChatApiWeb.AccountScopingTest do
  @moduledoc """
  Integration proof that protected controller actions scope by the request's
  resolved account (`Accounts.get_current_account_id/1`) rather than the current
  user's primary account.

  Scenario: user `U` has primary account `A` and is ALSO a member of account `B`.
  With no `x-account-id` header the request operates on `A` (primary); with
  `x-account-id: B` it operates on `B`. A non-member account id in the header is
  rejected with 403 by `CurrentAccountPlug`.
  """
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApi.{Accounts, Conversations, Customers, Tags}

  setup %{conn: conn} do
    account_a = insert(:account)
    account_b = insert(:account)
    # `insert(:user, ...)` mirrors membership for the primary account (A).
    user = insert(:user, account: account_a)
    # Make U a member of B as well (multi-account membership).
    {:ok, _} = Accounts.create_account_user(account_b.id, user.id, "user")

    # Resources in each account.
    customer_a = insert(:customer, account: account_a)
    customer_b = insert(:customer, account: account_b)
    conversation_a = insert(:conversation, account: account_a, customer: customer_a)
    conversation_b = insert(:conversation, account: account_b, customer: customer_b)

    conn = put_req_header(conn, "accept", "application/json")
    authed_conn = Pow.Plug.assign_current_user(conn, user, [])

    {:ok,
     authed_conn: authed_conn,
     user: user,
     account_a: account_a,
     account_b: account_b,
     customer_a: customer_a,
     customer_b: customer_b,
     conversation_a: conversation_a,
     conversation_b: conversation_b}
  end

  defp for_account(conn, account), do: put_req_header(conn, "x-account-id", account.id)

  describe "conversations read scoping (GET /api/conversations)" do
    test "with no header returns the primary account's conversations", %{
      authed_conn: authed_conn,
      conversation_a: conversation_a
    } do
      resp = get(authed_conn, Routes.conversation_path(authed_conn, :index))
      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [conversation_a.id]
    end

    test "with x-account-id: B returns account B's conversations, not A's", %{
      authed_conn: authed_conn,
      account_b: account_b,
      conversation_b: conversation_b
    } do
      resp =
        authed_conn
        |> for_account(account_b)
        |> get(Routes.conversation_path(authed_conn, :index))

      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [conversation_b.id]
    end

    test "cannot show account B's conversation without the header (scoped to A)", %{
      authed_conn: authed_conn,
      conversation_b: conversation_b
    } do
      # No header -> resolves to A; the per-resource authorize plug must reject
      # a conversation that belongs to B.
      resp = get(authed_conn, Routes.conversation_path(authed_conn, :show, conversation_b.id))

      assert json_response(resp, 404)
    end

    test "can show account B's conversation with x-account-id: B", %{
      authed_conn: authed_conn,
      account_b: account_b,
      conversation_b: conversation_b
    } do
      resp =
        authed_conn
        |> for_account(account_b)
        |> get(Routes.conversation_path(authed_conn, :show, conversation_b.id))

      assert json_response(resp, 200)["data"]["id"] == conversation_b.id
    end
  end

  describe "customers read scoping (GET /api/customers)" do
    test "with no header returns the primary account's customers", %{
      authed_conn: authed_conn,
      customer_a: customer_a
    } do
      resp = get(authed_conn, Routes.customer_path(authed_conn, :index))
      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [customer_a.id]
    end

    test "with x-account-id: B returns account B's customers, not A's", %{
      authed_conn: authed_conn,
      account_b: account_b,
      customer_b: customer_b
    } do
      resp =
        authed_conn
        |> for_account(account_b)
        |> get(Routes.customer_path(authed_conn, :index))

      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [customer_b.id]
    end
  end

  describe "create scoping (POST /api/tags — protected create)" do
    test "persists the resource under the resolved account B", %{
      authed_conn: authed_conn,
      account_a: account_a,
      account_b: account_b
    } do
      attrs = params_for(:tag, name: "scoped-to-b")

      resp =
        authed_conn
        |> for_account(account_b)
        |> post(Routes.tag_path(authed_conn, :create), tag: attrs)

      assert %{"id" => id} = json_response(resp, 201)["data"]

      # The persisted tag belongs to B, not to the user's primary account A.
      tag = Tags.get_tag!(id)
      assert tag.account_id == account_b.id
      refute tag.account_id == account_a.id

      # And it is visible when listing tags for B...
      resp_b =
        authed_conn
        |> for_account(account_b)
        |> get(Routes.tag_path(authed_conn, :index))

      assert json_response(resp_b, 200)["data"] |> Enum.map(& &1["id"]) == [id]

      # ...but NOT when listing tags for the primary account A.
      resp_a = get(authed_conn, Routes.tag_path(authed_conn, :index))
      assert json_response(resp_a, 200)["data"] == []
    end
  end

  describe "non-member account id is rejected" do
    test "GET /api/conversations with a non-member x-account-id returns 403", %{
      authed_conn: authed_conn
    } do
      # A brand new account that U is NOT a member of.
      stranger_account = insert(:account)

      resp =
        authed_conn
        |> for_account(stranger_account)
        |> get(Routes.conversation_path(authed_conn, :index))

      assert json_response(resp, 403)["error"]["message"] =~ "not a member"
    end
  end

  # Fix 1: conversation nested routes (add_tag/remove_tag/previous/related/share)
  # must be account-scoped by the `authorize` plug.
  describe "conversation nested-route scoping (IDOR)" do
    test "add_tag on account B's conversation with x-account-id: A -> 404, no mutation", %{
      authed_conn: authed_conn,
      account_a: account_a,
      conversation_b: conversation_b
    } do
      tag_a = insert(:tag, account: account_a, name: "tag-a")

      # No header -> resolves to A; the conversation lives in B.
      resp =
        post(authed_conn, Routes.conversation_path(authed_conn, :add_tag, conversation_b),
          tag_id: tag_a.id
        )

      assert json_response(resp, 404)
      assert Conversations.get_conversation!(conversation_b.id).tags == []
    end

    test "add_tag with a foreign tag from account C -> 404, no mutation", %{
      authed_conn: authed_conn,
      account_a: account_a,
      conversation_a: conversation_a
    } do
      # U is NOT a member of C, and the tag lives in C.
      account_c = insert(:account)
      tag_c = insert(:tag, account: account_c, name: "tag-c")

      resp =
        authed_conn
        |> for_account(account_a)
        |> post(Routes.conversation_path(authed_conn, :add_tag, conversation_a), tag_id: tag_c.id)

      assert json_response(resp, 404)
      assert Conversations.get_conversation!(conversation_a.id).tags == []
    end

    test "add_tag succeeds for a same-account tag with the correct header", %{
      authed_conn: authed_conn,
      account_b: account_b,
      conversation_b: conversation_b
    } do
      tag_b = insert(:tag, account: account_b, name: "tag-b")

      resp =
        authed_conn
        |> for_account(account_b)
        |> post(Routes.conversation_path(authed_conn, :add_tag, conversation_b), tag_id: tag_b.id)

      assert json_response(resp, 200)["data"]["ok"]
      assert [%{name: "tag-b"}] = Conversations.get_conversation!(conversation_b.id).tags
    end

    test "previous on account B's conversation with x-account-id: A -> 404", %{
      authed_conn: authed_conn,
      conversation_b: conversation_b
    } do
      resp = get(authed_conn, Routes.conversation_path(authed_conn, :previous, conversation_b))
      assert json_response(resp, 404)
    end

    test "related on account B's conversation with x-account-id: A -> 404", %{
      authed_conn: authed_conn,
      conversation_b: conversation_b
    } do
      resp = get(authed_conn, Routes.conversation_path(authed_conn, :related, conversation_b))
      assert json_response(resp, 404)
    end

    test "share on account B's conversation with x-account-id: A -> 404", %{
      authed_conn: authed_conn,
      conversation_b: conversation_b
    } do
      resp = post(authed_conn, Routes.conversation_path(authed_conn, :share, conversation_b))
      assert json_response(resp, 404)
    end

    test "share succeeds (and signs the resolved account) with the correct header", %{
      authed_conn: authed_conn,
      account_b: account_b,
      conversation_b: conversation_b
    } do
      resp =
        authed_conn
        |> for_account(account_b)
        |> post(Routes.conversation_path(authed_conn, :share, conversation_b))

      assert %{"ok" => true, "token" => token} = json_response(resp, 200)["data"]

      assert {:ok, {account_id, _customer_id}} =
               Phoenix.Token.verify(ChatApiWeb.Endpoint, conversation_b.id, token,
                 max_age: 86_400
               )

      assert account_id == account_b.id
    end
  end

  # Fix 2: customer nested routes (add_tag/remove_tag/link_issue/unlink_issue).
  describe "customer nested-route scoping (IDOR)" do
    test "add_tag on account B's customer with x-account-id: A -> 404, no mutation", %{
      authed_conn: authed_conn,
      account_a: account_a,
      customer_b: customer_b
    } do
      tag_a = insert(:tag, account: account_a, name: "cust-tag-a")

      resp =
        post(authed_conn, Routes.customer_path(authed_conn, :add_tag, customer_b),
          tag_id: tag_a.id
        )

      assert json_response(resp, 404)
      assert Customers.get_customer!(customer_b.id, [:tags]).tags == []
    end

    test "add_tag with a foreign tag from account C -> 404, no mutation", %{
      authed_conn: authed_conn,
      account_a: account_a,
      customer_a: customer_a
    } do
      account_c = insert(:account)
      tag_c = insert(:tag, account: account_c, name: "cust-tag-c")

      resp =
        authed_conn
        |> for_account(account_a)
        |> post(Routes.customer_path(authed_conn, :add_tag, customer_a), tag_id: tag_c.id)

      assert json_response(resp, 404)
      assert Customers.get_customer!(customer_a.id, [:tags]).tags == []
    end

    test "link_issue with a foreign issue from account C -> 404, no mutation", %{
      authed_conn: authed_conn,
      account_a: account_a,
      customer_a: customer_a
    } do
      account_c = insert(:account)
      issue_c = insert(:issue, account: account_c)

      resp =
        authed_conn
        |> for_account(account_a)
        |> post(Routes.customer_path(authed_conn, :link_issue, customer_a), issue_id: issue_c.id)

      assert json_response(resp, 404)
      assert Customers.get_customer!(customer_a.id, [:issues]).issues == []
    end

    test "link_issue on account B's customer with x-account-id: A -> 404", %{
      authed_conn: authed_conn,
      account_b: account_b,
      customer_b: customer_b
    } do
      issue_b = insert(:issue, account: account_b)

      resp =
        post(authed_conn, Routes.customer_path(authed_conn, :link_issue, customer_b),
          issue_id: issue_b.id
        )

      assert json_response(resp, 404)
      assert Customers.get_customer!(customer_b.id, [:issues]).issues == []
    end

    test "add_tag succeeds for a same-account tag with the correct header", %{
      authed_conn: authed_conn,
      account_b: account_b,
      customer_b: customer_b
    } do
      tag_b = insert(:tag, account: account_b, name: "cust-tag-b")

      resp =
        authed_conn
        |> for_account(account_b)
        |> post(Routes.customer_path(authed_conn, :add_tag, customer_b), tag_id: tag_b.id)

      assert json_response(resp, 200)["data"]["ok"]
      assert [%{name: "cust-tag-b"}] = Customers.get_customer!(customer_b.id, [:tags]).tags
    end
  end

  # Fix 3: renaming/deleting the resolved account is admin-only.
  describe "account update/delete require admin of the resolved account" do
    test "non-admin member cannot PUT /api/accounts for account B (403)", %{
      authed_conn: authed_conn,
      account_b: account_b
    } do
      # U is a member of B with role "user" (see setup), not an admin.
      resp =
        authed_conn
        |> for_account(account_b)
        |> put(Routes.account_path(authed_conn, :update, account_b),
          account: %{company_name: "hijacked"}
        )

      assert json_response(resp, 403)
      assert Accounts.get_account!(account_b.id).company_name != "hijacked"
    end

    test "non-admin member cannot DELETE /api/accounts for account B (403)", %{
      authed_conn: authed_conn,
      account_b: account_b
    } do
      resp =
        authed_conn
        |> for_account(account_b)
        |> delete(Routes.account_path(authed_conn, :delete, account_b))

      assert json_response(resp, 403)
      assert Accounts.get_account!(account_b.id)
    end

    test "an admin of the resolved account can PUT /api/accounts", %{conn: conn} do
      account = insert(:account)
      admin = insert(:user, account: account, role: "admin")
      admin_conn = Pow.Plug.assign_current_user(conn, admin, [])

      resp =
        put(admin_conn, Routes.account_path(admin_conn, :update, account),
          account: %{company_name: "renamed-by-admin"}
        )

      assert json_response(resp, 200)["data"]["company_name"] == "renamed-by-admin"
    end
  end

  # Fix 4: a malformed x-account-id header fails closed (403), never 500.
  describe "malformed x-account-id header" do
    test "GET /api/conversations with a non-UUID header returns 403 (not 500)", %{
      authed_conn: authed_conn
    } do
      resp =
        authed_conn
        |> put_req_header("x-account-id", "not-a-uuid")
        |> get(Routes.conversation_path(authed_conn, :index))

      assert json_response(resp, 403)["error"]["message"] =~ "not a member"
    end
  end
end
