defmodule ChatApiWeb.AccountMemberControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApi.Accounts

  setup %{conn: conn} do
    account = insert(:account)
    # Factory mirrors the role into the `account_users` membership row.
    admin = insert(:user, account: account, role: "admin")
    # An existing user in a different (their own) workspace.
    invitee = insert(:user)

    conn = put_req_header(conn, "accept", "application/json")
    admin_conn = Pow.Plug.assign_current_user(conn, admin, [])

    {:ok, conn: conn, admin_conn: admin_conn, account: account, admin: admin, invitee: invitee}
  end

  describe "POST /api/account_members" do
    test "an admin can add an existing user by email", %{
      admin_conn: admin_conn,
      account: account,
      invitee: invitee
    } do
      # Before being added, the invitee cannot access the account.
      invitee_conn = Pow.Plug.assign_current_user(build_conn(), invitee, [])

      resp =
        invitee_conn
        |> put_req_header("x-account-id", account.id)
        |> get(Routes.account_path(invitee_conn, :me))

      assert json_response(resp, 403)

      resp = post(admin_conn, "/api/account_members", %{email: invitee.email})

      assert %{
               "account_id" => account_id,
               "user_id" => user_id,
               "role" => "user",
               "email" => email
             } = json_response(resp, 200)["data"]

      assert account_id == account.id
      assert user_id == invitee.id
      assert email == invitee.email

      # The membership exists...
      assert %{role: "user"} = Accounts.get_account_user(invitee.id, account.id)

      # ...and the invitee can now access the account with the header.
      resp =
        invitee_conn
        |> put_req_header("x-account-id", account.id)
        |> get(Routes.account_path(invitee_conn, :me))

      assert json_response(resp, 200)["data"]["id"] == account.id
    end

    test "an admin can add a member with the admin role", %{
      admin_conn: admin_conn,
      account: account,
      invitee: invitee
    } do
      resp = post(admin_conn, "/api/account_members", %{email: invitee.email, role: "admin"})

      assert %{"role" => "admin"} = json_response(resp, 200)["data"]
      assert %{role: "admin"} = Accounts.get_account_user(invitee.id, account.id)
    end

    test "a non-admin member cannot add members (403)", %{
      conn: conn,
      account: account,
      invitee: invitee
    } do
      member = insert(:user, account: account, role: "user")
      member_conn = Pow.Plug.assign_current_user(conn, member, [])

      resp = post(member_conn, "/api/account_members", %{email: invitee.email})

      assert json_response(resp, 403)
      refute Accounts.get_account_user(invitee.id, account.id)
    end

    test "an admin of another account cannot add members to this one (403)", %{
      conn: conn,
      account: account,
      invitee: invitee
    } do
      # Admin of their OWN account, but only a "user" member of `account`.
      outsider = insert(:user, role: "admin")
      {:ok, _} = Accounts.create_account_user(account.id, outsider.id, "user")
      outsider_conn = Pow.Plug.assign_current_user(conn, outsider, [])

      resp =
        outsider_conn
        |> put_req_header("x-account-id", account.id)
        |> post("/api/account_members", %{email: invitee.email})

      assert json_response(resp, 403)
      refute Accounts.get_account_user(invitee.id, account.id)
    end

    test "unknown email returns 404", %{admin_conn: admin_conn} do
      resp = post(admin_conn, "/api/account_members", %{email: "nobody@example.com"})

      assert %{"status" => 404, "message" => "No user found with that email"} =
               json_response(resp, 404)["error"]
    end

    test "duplicate add is idempotent and preserves the existing role", %{
      admin_conn: admin_conn,
      account: account,
      invitee: invitee
    } do
      # Existing membership with the "admin" role...
      {:ok, _} = Accounts.create_account_user(account.id, invitee.id, "admin")

      # ...adding again with role "user" must NOT overwrite it.
      resp = post(admin_conn, "/api/account_members", %{email: invitee.email, role: "user"})

      assert %{"role" => "admin"} = json_response(resp, 200)["data"]
      assert %{role: "admin"} = Accounts.get_account_user(invitee.id, account.id)
    end

    test "invalid role returns 422", %{
      admin_conn: admin_conn,
      account: account,
      invitee: invitee
    } do
      resp = post(admin_conn, "/api/account_members", %{email: invitee.email, role: "owner"})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
      refute Accounts.get_account_user(invitee.id, account.id)
    end

    test "unauthenticated request returns 401", %{conn: conn, invitee: invitee} do
      resp = post(conn, "/api/account_members", %{email: invitee.email})

      assert resp.status == 401
    end
  end

  describe "PUT /api/account_members/:user_id" do
    setup %{account: account} do
      # A member of `account` whose PRIMARY workspace is elsewhere.
      member = insert(:user)
      {:ok, _} = Accounts.create_account_user(account.id, member.id, "user")

      {:ok, member: member}
    end

    test "an admin can promote a member to admin", %{
      admin_conn: admin_conn,
      account: account,
      member: member
    } do
      resp = put(admin_conn, "/api/account_members/#{member.id}", %{role: "admin"})

      assert %{
               "account_id" => account_id,
               "user_id" => user_id,
               "role" => "admin",
               "email" => email
             } = json_response(resp, 200)["data"]

      assert account_id == account.id
      assert user_id == member.id
      assert email == member.email
      assert %{role: "admin"} = Accounts.get_account_user(member.id, account.id)
    end

    test "an admin can demote another admin when they are not the last one", %{
      admin_conn: admin_conn,
      account: account,
      member: member
    } do
      # Two admins: the setup admin and the (promoted) member.
      {:ok, _} =
        Accounts.get_account_user(member.id, account.id)
        |> Accounts.update_account_user_role("admin")

      resp = put(admin_conn, "/api/account_members/#{member.id}", %{role: "user"})

      assert %{"role" => "user"} = json_response(resp, 200)["data"]
      assert %{role: "user"} = Accounts.get_account_user(member.id, account.id)
    end

    test "a superadmin who is NOT a member can change roles", %{
      conn: conn,
      account: account,
      member: member
    } do
      superadmin = insert(:superadmin)
      refute Accounts.get_account_user(superadmin.id, account.id)

      resp =
        conn
        |> Pow.Plug.assign_current_user(superadmin, [])
        |> put_req_header("x-account-id", account.id)
        |> put("/api/account_members/#{member.id}", %{role: "admin"})

      assert %{"role" => "admin"} = json_response(resp, 200)["data"]
      assert %{role: "admin"} = Accounts.get_account_user(member.id, account.id)
    end

    test "a non-admin member cannot change roles (403)", %{
      conn: conn,
      account: account,
      member: member
    } do
      other_member = insert(:user, account: account, role: "user")
      member_conn = Pow.Plug.assign_current_user(conn, other_member, [])

      resp = put(member_conn, "/api/account_members/#{member.id}", %{role: "admin"})

      assert json_response(resp, 403)
      assert %{role: "user"} = Accounts.get_account_user(member.id, account.id)
    end

    test "404 when the target user is not a member", %{admin_conn: admin_conn} do
      stranger = insert(:user)

      resp = put(admin_conn, "/api/account_members/#{stranger.id}", %{role: "admin"})

      assert %{"status" => 404} = json_response(resp, 404)["error"]
    end

    test "422 for an invalid role", %{
      admin_conn: admin_conn,
      account: account,
      member: member
    } do
      resp = put(admin_conn, "/api/account_members/#{member.id}", %{role: "owner"})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
      assert %{role: "user"} = Accounts.get_account_user(member.id, account.id)
    end

    test "422 when demoting the LAST admin of the workspace", %{
      admin_conn: admin_conn,
      account: account,
      admin: admin
    } do
      # The setup admin is the only admin of `account`.
      resp = put(admin_conn, "/api/account_members/#{admin.id}", %{role: "user"})

      assert %{"status" => 422, "message" => message} = json_response(resp, 422)["error"]
      assert message =~ "last admin"
      assert %{role: "admin"} = Accounts.get_account_user(admin.id, account.id)
    end

    test "the last-admin guard applies to superadmins too", %{
      conn: conn,
      account: account,
      admin: admin
    } do
      superadmin = insert(:superadmin)

      resp =
        conn
        |> Pow.Plug.assign_current_user(superadmin, [])
        |> put_req_header("x-account-id", account.id)
        |> put("/api/account_members/#{admin.id}", %{role: "user"})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
      assert %{role: "admin"} = Accounts.get_account_user(admin.id, account.id)
    end

    test "unauthenticated request returns 401", %{conn: conn, member: member} do
      resp = put(conn, "/api/account_members/#{member.id}", %{role: "admin"})

      assert resp.status == 401
    end
  end

  describe "DELETE /api/account_members/:user_id" do
    setup %{account: account} do
      # A member of `account` whose PRIMARY workspace is elsewhere.
      member = insert(:user)
      {:ok, _} = Accounts.create_account_user(account.id, member.id, "user")

      {:ok, member: member}
    end

    test "an admin can remove a non-primary member (204)", %{
      admin_conn: admin_conn,
      account: account,
      member: member
    } do
      resp = delete(admin_conn, "/api/account_members/#{member.id}")

      assert response(resp, 204)
      refute Accounts.get_account_user(member.id, account.id)
    end

    test "a superadmin can remove members of a foreign workspace (204)", %{
      conn: conn,
      account: account,
      member: member
    } do
      superadmin = insert(:superadmin)

      resp =
        conn
        |> Pow.Plug.assign_current_user(superadmin, [])
        |> put_req_header("x-account-id", account.id)
        |> delete("/api/account_members/#{member.id}")

      assert response(resp, 204)
      refute Accounts.get_account_user(member.id, account.id)
    end

    test "422 when removing a member from their primary workspace", %{
      admin_conn: admin_conn,
      account: account
    } do
      native = insert(:user, account: account, role: "user")

      resp = delete(admin_conn, "/api/account_members/#{native.id}")

      assert %{
               "status" => 422,
               "message" => "Cannot remove a member from their primary workspace."
             } = json_response(resp, 422)["error"]

      assert Accounts.get_account_user(native.id, account.id)
    end

    test "422 when removing the LAST admin membership of the workspace", %{conn: conn} do
      # A workspace whose ONLY admin has their primary account elsewhere, so
      # the primary-workspace guard does not apply — only the last-admin one.
      workspace = insert(:account)
      only_admin = insert(:user)
      {:ok, _} = Accounts.create_account_user(workspace.id, only_admin.id, "admin")

      resp =
        conn
        |> Pow.Plug.assign_current_user(only_admin, [])
        |> put_req_header("x-account-id", workspace.id)
        |> delete("/api/account_members/#{only_admin.id}")

      assert %{"status" => 422, "message" => message} = json_response(resp, 422)["error"]
      assert message =~ "last admin"
      assert Accounts.get_account_user(only_admin.id, workspace.id)
    end

    test "404 when the target user is not a member", %{admin_conn: admin_conn} do
      stranger = insert(:user)

      resp = delete(admin_conn, "/api/account_members/#{stranger.id}")

      assert %{"status" => 404} = json_response(resp, 404)["error"]
    end

    test "a non-admin member cannot remove members (403)", %{
      conn: conn,
      account: account,
      member: member
    } do
      other_member = insert(:user, account: account, role: "user")
      member_conn = Pow.Plug.assign_current_user(conn, other_member, [])

      resp = delete(member_conn, "/api/account_members/#{member.id}")

      assert json_response(resp, 403)
      assert Accounts.get_account_user(member.id, account.id)
    end

    test "unauthenticated request returns 401", %{conn: conn, member: member} do
      resp = delete(conn, "/api/account_members/#{member.id}")

      assert resp.status == 401
    end
  end
end
