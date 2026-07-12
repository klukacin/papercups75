defmodule ChatApiWeb.AdminUserControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApi.Accounts

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")

    {:ok, conn: conn}
  end

  describe "GET /api/admin/users" do
    test "a superadmin sees EVERY user on the instance with their memberships", %{conn: conn} do
      account_a = insert(:account, company_name: "Acme A")
      account_b = insert(:account, company_name: "Acme B")

      superadmin = insert(:user, account: account_a, role: "admin", is_superadmin: true)
      member = insert(:user, account: account_b, role: "user")
      insert(:user_profile, user: member, display_name: "Membo")
      # `member` is ALSO an admin member of account A (multi-account membership).
      {:ok, _} = Accounts.create_account_user(account_a.id, member.id, "admin")

      authed_conn = Pow.Plug.assign_current_user(conn, superadmin, [])
      resp = get(authed_conn, "/api/admin/users")

      data = json_response(resp, 200)["data"]
      assert length(data) == 2

      by_id = Map.new(data, &{&1["id"], &1})

      superadmin_json = Map.fetch!(by_id, superadmin.id)
      assert superadmin_json["email"] == superadmin.email
      assert superadmin_json["is_superadmin"] == true
      assert superadmin_json["disabled_at"] == nil
      assert superadmin_json["archived_at"] == nil

      assert [%{"account_id" => a_id, "company_name" => "Acme A", "role" => "admin"}] =
               superadmin_json["memberships"]

      assert a_id == account_a.id

      member_json = Map.fetch!(by_id, member.id)
      assert member_json["email"] == member.email
      assert member_json["is_superadmin"] == false
      assert member_json["display_name"] == "Membo"

      memberships = Enum.sort_by(member_json["memberships"], & &1["company_name"])

      assert [
               %{"account_id" => membership_a, "company_name" => "Acme A", "role" => "admin"},
               %{"account_id" => membership_b, "company_name" => "Acme B", "role" => "user"}
             ] = memberships

      assert membership_a == account_a.id
      assert membership_b == account_b.id
    end

    test "includes disabled_at/archived_at for inactive users", %{conn: conn} do
      superadmin = insert(:user, is_superadmin: true)
      disabled = insert(:user, disabled_at: ~U[2021-01-01 00:00:00Z])
      archived = insert(:user, archived_at: ~U[2021-02-02 00:00:00Z])

      authed_conn = Pow.Plug.assign_current_user(conn, superadmin, [])
      resp = get(authed_conn, "/api/admin/users")

      by_id = resp |> json_response(200) |> Map.fetch!("data") |> Map.new(&{&1["id"], &1})

      assert by_id[disabled.id]["disabled_at"]
      assert by_id[archived.id]["archived_at"]
    end

    test "a regular user gets 403 (workspace admins included)", %{conn: conn} do
      admin = insert(:user, role: "admin")
      authed_conn = Pow.Plug.assign_current_user(conn, admin, [])

      resp = get(authed_conn, "/api/admin/users")

      assert %{"status" => 403} = json_response(resp, 403)["error"]
    end

    test "an unauthenticated request returns 401", %{conn: conn} do
      resp = get(conn, "/api/admin/users")

      assert resp.status == 401
    end
  end
end
