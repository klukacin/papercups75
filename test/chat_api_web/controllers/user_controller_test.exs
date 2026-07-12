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

  describe "update superadmin (PUT /api/users/:id/superadmin)" do
    setup %{conn: conn} do
      superadmin = insert(:user, is_superadmin: true)
      super_conn = Pow.Plug.assign_current_user(conn, superadmin, [])

      {:ok, superadmin: superadmin, super_conn: super_conn}
    end

    test "a superadmin can grant superadmin access to another user", %{super_conn: super_conn} do
      target = insert(:user)

      resp = put(super_conn, "/api/users/#{target.id}/superadmin", %{is_superadmin: true})

      assert %{"id" => id, "is_superadmin" => true} = json_response(resp, 200)["data"]
      assert id == target.id
      assert ChatApi.Accounts.superadmin?(target.id)
    end

    test "a superadmin can revoke another superadmin's access", %{super_conn: super_conn} do
      target = insert(:user, is_superadmin: true)

      resp = put(super_conn, "/api/users/#{target.id}/superadmin", %{is_superadmin: false})

      assert %{"is_superadmin" => false} = json_response(resp, 200)["data"]
      refute ChatApi.Accounts.superadmin?(target.id)
    end

    test "granting is idempotent", %{super_conn: super_conn} do
      target = insert(:user, is_superadmin: true)

      resp = put(super_conn, "/api/users/#{target.id}/superadmin", %{is_superadmin: true})

      assert %{"is_superadmin" => true} = json_response(resp, 200)["data"]
      assert ChatApi.Accounts.superadmin?(target.id)
    end

    test "a non-superadmin cannot grant superadmin access (403)", %{conn: conn} do
      # A workspace ADMIN is still not an instance admin.
      admin = insert(:user, role: "admin")
      target = insert(:user)
      admin_conn = Pow.Plug.assign_current_user(conn, admin, [])

      resp = put(admin_conn, "/api/users/#{target.id}/superadmin", %{is_superadmin: true})

      assert json_response(resp, 403)
      refute ChatApi.Accounts.superadmin?(target.id)
    end

    test "a superadmin cannot revoke their own access (422)", %{
      super_conn: super_conn,
      superadmin: superadmin
    } do
      # Another superadmin exists, so this is purely the self-revoke guard.
      _other = insert(:user, is_superadmin: true)

      resp = put(super_conn, "/api/users/#{superadmin.id}/superadmin", %{is_superadmin: false})

      assert %{
               "status" => 422,
               "message" => "You cannot revoke your own instance-admin access."
             } = json_response(resp, 422)["error"]

      assert ChatApi.Accounts.superadmin?(superadmin.id)
    end

    test "the LAST superadmin cannot be revoked (422)", %{
      super_conn: super_conn,
      superadmin: superadmin
    } do
      # `superadmin` is the only superadmin on the instance.
      resp = put(super_conn, "/api/users/#{superadmin.id}/superadmin", %{is_superadmin: false})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
      assert ChatApi.Accounts.superadmin?(superadmin.id)
    end

    test "a non-boolean is_superadmin value returns 422", %{super_conn: super_conn} do
      target = insert(:user)

      resp = put(super_conn, "/api/users/#{target.id}/superadmin", %{is_superadmin: "yes"})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
      refute ChatApi.Accounts.superadmin?(target.id)
    end

    test "an unknown user id returns 404", %{super_conn: super_conn} do
      resp = put(super_conn, "/api/users/999999999/superadmin", %{is_superadmin: true})

      assert json_response(resp, 404)
    end

    test "an unauthenticated request returns 401", %{conn: conn} do
      target = insert(:user)

      resp =
        conn
        |> put_req_header("accept", "application/json")
        |> put("/api/users/#{target.id}/superadmin", %{is_superadmin: true})

      assert resp.status == 401
    end
  end

  describe "update role ignores superadmin params" do
    test "PUT /api/users/:id/role cannot set is_superadmin", %{conn: conn} do
      account = insert(:account)
      admin = insert(:user, account: account, role: "admin")
      target = insert(:user, account: account, role: "user")
      admin_conn = Pow.Plug.assign_current_user(conn, admin, [])

      resp =
        put(admin_conn, "/api/users/#{target.id}/role", %{role: "admin", is_superadmin: true})

      assert json_response(resp, 200)

      reloaded = Users.find_by_id!(target.id)
      assert reloaded.role == "admin"
      refute reloaded.is_superadmin
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
