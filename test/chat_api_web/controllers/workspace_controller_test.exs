defmodule ChatApiWeb.WorkspaceControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApi.{Accounts, Inboxes, Users}

  setup %{conn: conn} do
    account = insert(:account)
    # Creating workspaces is an instance-superadmin-only operation.
    user = insert(:user, account: account, role: "admin", is_superadmin: true)

    conn = put_req_header(conn, "accept", "application/json")
    authed_conn = Pow.Plug.assign_current_user(conn, user, [])

    {:ok, conn: conn, authed_conn: authed_conn, account: account, user: user}
  end

  describe "POST /api/workspaces" do
    test "a regular user cannot create workspaces (403)", %{conn: conn} do
      # Even a workspace ADMIN is not allowed — only instance superadmins are.
      regular_admin = insert(:user, role: "admin")
      regular_conn = Pow.Plug.assign_current_user(conn, regular_admin, [])

      resp = post(regular_conn, "/api/workspaces", %{company_name: "Not Allowed Inc"})

      assert %{"status" => 403, "message" => "Only instance admins can create workspaces."} =
               json_response(resp, 403)["error"]

      refute Enum.any?(Accounts.list_accounts(), &(&1.company_name == "Not Allowed Inc"))
    end

    test "creates a new account with an admin membership for the creator", %{
      authed_conn: authed_conn,
      account: account,
      user: user
    } do
      resp = post(authed_conn, "/api/workspaces", %{company_name: "New Workspace"})

      assert %{
               "id" => id,
               "object" => "account",
               "company_name" => "New Workspace"
             } = json_response(resp, 201)["data"]

      # The creator is an admin member of the new workspace...
      assert %{role: "admin"} = Accounts.get_account_user(user.id, id)
      # ...but their primary account is unchanged.
      assert Users.find_by_id!(user.id).account_id == account.id

      # The new workspace gets a primary inbox (like registration).
      assert %{name: "Primary Inbox", is_primary: true} = Inboxes.get_account_primary_inbox(id)
    end

    test "the creator sees both workspaces and can access the new one via x-account-id", %{
      authed_conn: authed_conn,
      account: account
    } do
      resp = post(authed_conn, "/api/workspaces", %{company_name: "Second Workspace"})
      assert %{"id" => id} = json_response(resp, 201)["data"]

      # GET /api/accounts lists BOTH workspaces.
      resp = get(authed_conn, Routes.account_path(authed_conn, :index))

      ids =
        resp
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])
        |> Enum.sort()

      assert Enum.sort([account.id, id]) == ids

      # And the new workspace is accessible with the x-account-id header.
      resp =
        authed_conn
        |> put_req_header("x-account-id", id)
        |> get(Routes.account_path(authed_conn, :me))

      assert json_response(resp, 200)["data"]["id"] == id
    end

    test "a second user is NOT a member of the new workspace (403)", %{
      conn: conn,
      authed_conn: authed_conn
    } do
      resp = post(authed_conn, "/api/workspaces", %{company_name: "Private Workspace"})
      assert %{"id" => id} = json_response(resp, 201)["data"]

      other_user = insert(:user)
      other_conn = Pow.Plug.assign_current_user(conn, other_user, [])

      resp =
        other_conn
        |> put_req_header("x-account-id", id)
        |> get(Routes.account_path(other_conn, :me))

      assert json_response(resp, 403)
    end

    test "empty company_name returns 422", %{authed_conn: authed_conn} do
      resp = post(authed_conn, "/api/workspaces", %{company_name: ""})

      assert %{"status" => 422, "errors" => errors} = json_response(resp, 422)["error"]
      assert %{"company_name" => [_ | _]} = errors
    end

    test "missing company_name returns 422", %{authed_conn: authed_conn} do
      resp = post(authed_conn, "/api/workspaces", %{})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
    end

    test "unauthenticated request returns 401", %{conn: conn} do
      resp = post(conn, "/api/workspaces", %{company_name: "Nope"})

      assert resp.status == 401
      refute Enum.any?(Accounts.list_accounts(), &(&1.company_name == "Nope"))
    end
  end
end
