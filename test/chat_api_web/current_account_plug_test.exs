defmodule ChatApiWeb.CurrentAccountPlugTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApiWeb.CurrentAccountPlug

  setup %{conn: conn} do
    account = insert(:account)
    # The factory mirrors primary-account membership on insert (matching
    # `Users.create_user/1`), so `user` is already a member of `account`.
    user = insert(:user, account: account)

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

  # These exercise the plug end-to-end through the `:api_protected` pipeline
  # (see router.ex) rather than calling `call/2` directly.
  describe ":api_protected pipeline wiring" do
    setup %{conn: conn, user: user} do
      authed_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> Pow.Plug.assign_current_user(user, [])

      {:ok, authed_conn: authed_conn}
    end

    test "with no x-account-id header, request succeeds and resolves the primary account",
         %{authed_conn: authed_conn, user: user, account: account} do
      conn = get(authed_conn, Routes.session_path(authed_conn, :me))

      assert json_response(conn, 200)
      assert conn.assigns.current_account_id == account.id
      assert conn.assigns.current_account_id == user.account_id
    end

    test "with x-account-id for an account the user IS a member of, resolves that account",
         %{authed_conn: authed_conn, user: user} do
      other_account = insert(:account)
      {:ok, _} = ChatApi.Accounts.create_account_user(other_account.id, user.id, "user")

      conn =
        authed_conn
        |> put_req_header("x-account-id", other_account.id)
        |> get(Routes.session_path(authed_conn, :me))

      assert json_response(conn, 200)
      assert conn.assigns.current_account_id == other_account.id
    end

    test "with x-account-id for an account the user is NOT a member of, returns 403",
         %{authed_conn: authed_conn} do
      foreign_account = insert(:account)

      conn =
        authed_conn
        |> put_req_header("x-account-id", foreign_account.id)
        |> get(Routes.session_path(authed_conn, :me))

      assert %{
               "error" => %{
                 "status" => 403,
                 "message" => "Forbidden: not a member of this account"
               }
             } = json_response(conn, 403)

      refute conn.assigns[:current_account_id]
    end
  end
end
