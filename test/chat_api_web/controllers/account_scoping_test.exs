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

  alias ChatApi.{Accounts, Tags}

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
end
