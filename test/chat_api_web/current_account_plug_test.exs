defmodule ChatApiWeb.CurrentAccountPlugTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApiWeb.CurrentAccountPlug

  setup %{conn: conn} do
    account = insert(:account)
    user = insert(:user, account: account)
    # Phase A mirroring: make the user a member of their primary account.
    insert(:account_user, user: user, account: account)

    {:ok, conn: conn, account: account, user: user}
  end

  describe "call/2" do
    test "returns conn unchanged when there is no current_user", %{conn: conn} do
      result = CurrentAccountPlug.call(conn, [])

      refute result.halted
      assert is_nil(result.assigns[:current_account_id])
    end

    test "with no header, assigns the user's primary account_id", %{
      conn: conn,
      user: user,
      account: account
    } do
      conn =
        conn
        |> Pow.Plug.assign_current_user(user, [])
        |> CurrentAccountPlug.call([])

      refute conn.halted
      assert conn.assigns.current_account_id == account.id
    end

    test "with x-account-id header for an account the user is a member of, assigns it", %{
      conn: conn,
      user: user
    } do
      other_account = insert(:account)
      insert(:account_user, user: user, account: other_account)

      conn =
        conn
        |> Pow.Plug.assign_current_user(user, [])
        |> put_req_header("x-account-id", other_account.id)
        |> CurrentAccountPlug.call([])

      refute conn.halted
      assert conn.assigns.current_account_id == other_account.id
    end

    test "with x-account-id header for an account the user is NOT a member of, returns 403 and halts",
         %{conn: conn, user: user} do
      foreign_account = insert(:account)

      conn =
        conn
        |> Pow.Plug.assign_current_user(user, [])
        |> put_req_header("x-account-id", foreign_account.id)
        |> CurrentAccountPlug.call([])

      assert conn.halted
      assert conn.status == 403
      assert is_nil(conn.assigns[:current_account_id])

      assert %{
               "error" => %{
                 "status" => 403,
                 "message" => "Forbidden: not a member of this account"
               }
             } = json_response(conn, 403)
    end
  end
end
