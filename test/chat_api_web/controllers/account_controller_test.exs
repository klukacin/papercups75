defmodule ChatApiWeb.AccountControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory
  alias ChatApi.Accounts.Account

  @create_attrs %{
    company_name: "some company_name"
  }
  @update_attrs %{
    company_name: "some updated company_name"
  }
  @invalid_attrs %{company_name: nil}

  def update_current_user_account(conn, account_id) do
    # `CurrentAccountPlug` (in the `:api_protected` pipeline) authorizes the
    # request by verifying the current user is a member of the resolved account,
    # so we need a persisted user that is a member of `account_id` (the factory
    # mirrors primary-account membership on insert).
    #
    # Renaming/deleting an account is admin-only, so the user is created with the
    # `admin` role (which the factory mirrors into the `account_users` row) — the
    # same role a user gets on the account they create during onboarding.
    account = ChatApi.Accounts.get_account!(account_id)
    user = insert(:user, account: account, role: "admin")
    Pow.Plug.assign_current_user(conn, user, [])
  end

  setup %{conn: conn} do
    account = insert(:account)
    conn = put_req_header(conn, "accept", "application/json")

    {:ok, conn: conn, account: account}
  end

  describe "index accounts (list current user's accounts)" do
    test "returns all accounts the current user is a member of", %{
      conn: conn,
      account: account
    } do
      # `account` is the user's primary account; add membership to a second one.
      second_account = insert(:account)
      user = insert(:user, account: account)
      {:ok, _} = ChatApi.Accounts.create_account_user(second_account.id, user.id, "user")

      authed_conn = Pow.Plug.assign_current_user(conn, user, [])
      resp = get(authed_conn, Routes.account_path(authed_conn, :index))

      ids =
        resp
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])
        |> Enum.sort()

      assert Enum.sort([account.id, second_account.id]) == ids
    end

    test "returns a single account for a single-account user", %{
      conn: conn,
      account: account
    } do
      user = insert(:user, account: account)
      authed_conn = Pow.Plug.assign_current_user(conn, user, [])

      resp = get(authed_conn, Routes.account_path(authed_conn, :index))
      data = json_response(resp, 200)["data"]

      assert [%{"id" => id}] = data
      assert id == account.id
    end

    test "a superadmin sees ALL accounts on the instance, ordered by creation", %{
      conn: conn,
      account: account
    } do
      # Deterministic creation order: `account` (from setup) is the oldest.
      earliest = NaiveDateTime.add(account.inserted_at, -3600, :second)
      older = insert(:account, inserted_at: earliest)

      newer =
        insert(:account, inserted_at: NaiveDateTime.add(account.inserted_at, 3600, :second))

      # The superadmin is only a MEMBER of their own primary account.
      superadmin = insert(:user, account: account, is_superadmin: true)
      authed_conn = Pow.Plug.assign_current_user(conn, superadmin, [])

      resp = get(authed_conn, Routes.account_path(authed_conn, :index))

      ids =
        resp
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert ids == [older.id, account.id, newer.id]
    end

    test "a regular user does NOT see foreign accounts", %{conn: conn, account: account} do
      _foreign = insert(:account)
      user = insert(:user, account: account)
      authed_conn = Pow.Plug.assign_current_user(conn, user, [])

      resp = get(authed_conn, Routes.account_path(authed_conn, :index))

      assert [%{"id" => id}] = json_response(resp, 200)["data"]
      assert id == account.id
    end
  end

  describe "create account" do
    test "renders account when data is valid", %{conn: conn} do
      resp = post(conn, Routes.account_path(conn, :create), account: @create_attrs)
      assert %{"id" => id} = json_response(resp, 201)["data"]

      authed_conn = update_current_user_account(conn, id)
      resp = get(authed_conn, Routes.account_path(authed_conn, :me))

      assert %{
               "id" => _id,
               "object" => "account",
               "company_name" => "some company_name"
             } = json_response(resp, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.account_path(conn, :create), account: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update account" do
    test "renders account when data is valid", %{
      conn: conn,
      account: %Account{id: id} = account
    } do
      authed_conn = update_current_user_account(conn, account.id)

      conn =
        put(authed_conn, Routes.account_path(authed_conn, :update, account),
          account: @update_attrs
        )

      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(authed_conn, Routes.account_path(authed_conn, :me))

      assert %{
               "id" => _id,
               "company_name" => "some updated company_name"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      account: account
    } do
      authed_conn = update_current_user_account(conn, account.id)

      conn =
        put(authed_conn, Routes.account_path(authed_conn, :update, account),
          account: @invalid_attrs
        )

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete account" do
    test "deletes chosen account", %{conn: conn, account: account} do
      authed_conn = update_current_user_account(conn, account.id)
      conn = delete(authed_conn, Routes.account_path(authed_conn, :delete, account))
      assert response(conn, 204)

      # Deleting the account cascade-deletes the user's membership row, so the
      # user is no longer a member of their (now-gone) primary account and
      # `CurrentAccountPlug` forbids the request before it reaches the controller.
      resp = get(authed_conn, Routes.account_path(authed_conn, :me))
      assert json_response(resp, 403)
    end
  end
end
