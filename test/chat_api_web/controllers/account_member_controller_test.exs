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
end
