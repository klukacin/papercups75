defmodule ChatApiWeb.UserControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory
  alias ChatApi.{Users, Repo}

  setup %{conn: conn} do
    user = insert(:user)

    conn = put_req_header(conn, "accept", "application/json")
    authed_conn = Pow.Plug.assign_current_user(conn, user, [])

    {:ok, conn: conn, authed_conn: authed_conn, user: user}
  end

  describe "index users (team listing)" do
    test "includes members added via account_users membership", %{conn: conn} do
      account = insert(:account)
      user = insert(:user, account: account)
      # A user whose PRIMARY account is elsewhere, added as a member.
      member = insert(:user)
      {:ok, _} = ChatApi.Accounts.create_account_user(account.id, member.id, "user")

      authed_conn = Pow.Plug.assign_current_user(conn, user, [])

      resp =
        authed_conn
        |> put_req_header("x-account-id", account.id)
        |> get(Routes.user_path(authed_conn, :index))

      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"]) |> Enum.sort()

      assert Enum.sort([user.id, member.id]) == ids
    end

    test "still excludes disabled users (including membership-only members)", %{conn: conn} do
      account = insert(:account)
      user = insert(:user, account: account)
      member = insert(:user, disabled_at: DateTime.utc_now())
      {:ok, _} = ChatApi.Accounts.create_account_user(account.id, member.id, "user")

      authed_conn = Pow.Plug.assign_current_user(conn, user, [])

      resp =
        authed_conn
        |> put_req_header("x-account-id", account.id)
        |> get(Routes.user_path(authed_conn, :index))

      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [user.id]
    end

    test "does not leak members of other accounts", %{conn: conn} do
      account = insert(:account)
      user = insert(:user, account: account)
      # A user in a completely separate account with no membership here.
      _stranger = insert(:user)

      authed_conn = Pow.Plug.assign_current_user(conn, user, [])
      resp = get(authed_conn, Routes.user_path(authed_conn, :index))

      ids = json_response(resp, 200)["data"] |> Enum.map(& &1["id"])

      assert ids == [user.id]
    end
  end

  describe "delete user" do
    test "deletes user",
         %{authed_conn: authed_conn, user: user} do
      resp = delete(authed_conn, Routes.user_path(authed_conn, :delete, user.id))
      assert Repo.get(Users.User, user.id) == nil
      assert %{"ok" => true} = json_response(resp, 200)["data"]
    end

    test "returns 403 (forbidden) when trying to delete other users", %{
      authed_conn: authed_conn,
      user: user
    } do
      resp = delete(authed_conn, Routes.user_path(authed_conn, :delete, user.id + 1))
      assert resp.status == 403
    end
  end
end
