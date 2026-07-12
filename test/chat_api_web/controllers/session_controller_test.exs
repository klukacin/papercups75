defmodule ChatApiWeb.SessionControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApi.Users
  alias ChatApi.Users.User

  @invalid_params %{"user" => %{"email" => "test@example.com", "password" => "invalid"}}

  setup do
    params =
      params_with_assocs(:user)
      |> with_password_confirmation()

    {:ok, user} = Users.create_user(params)

    # Pow clears the virtual :password field after hashing it into
    # :password_hash, so restore the plaintext password on the struct to let
    # these tests authenticate with it via auth_params/1.
    {:ok, user: %{user | password: params.password}}
  end

  def auth_params(%User{} = user) do
    %{"user" => %{"email" => user.email, "password" => user.password}}
  end

  describe "create/2" do
    test "with valid params", %{conn: conn, user: user} do
      conn = post(conn, Routes.session_path(conn, :create, auth_params(user)))

      assert json = json_response(conn, 200)
      assert json["data"]["token"]
      assert json["data"]["renew_token"]
    end

    test "with invalid params", %{conn: conn} do
      conn = post(conn, Routes.session_path(conn, :create, @invalid_params))

      assert json = json_response(conn, 401)
      assert json["error"]["message"] == "Invalid email or password"
      assert json["error"]["status"] == 401
    end

    test "with disabled user", %{conn: conn, user: user} do
      {:ok, _user} = Users.disable_user(user)
      resp = post(conn, Routes.session_path(conn, :create, auth_params(user)))

      assert json = json_response(resp, 401)
      assert "Your account is disabled" <> _msg = json["error"]["message"]
      assert json["error"]["status"] == 401
    end
  end

  describe "renew/2" do
    setup %{conn: conn, user: user} do
      authed_conn = post(conn, Routes.session_path(conn, :create, auth_params(user)))
      :timer.sleep(100)

      {:ok, renewal_token: authed_conn.private[:api_renew_token]}
    end

    test "with valid authorization header", %{conn: conn, renewal_token: token} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", token)
        |> post(Routes.session_path(conn, :renew))

      assert json = json_response(conn, 200)
      assert json["data"]["token"]
      assert json["data"]["renew_token"]
    end

    test "with invalid authorization header", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "invalid")
        |> post(Routes.session_path(conn, :renew))

      assert json = json_response(conn, 401)
      assert json["error"]["message"] == "Invalid token"
      assert json["error"]["status"] == 401
    end

    test "with disabled user", %{conn: conn, user: user, renewal_token: token} do
      {:ok, _user} = Users.disable_user(user)

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", token)
        |> post(Routes.session_path(conn, :renew))

      assert json = json_response(conn, 401)
      assert "Your account is disabled" <> _msg = json["error"]["message"]
      assert json["error"]["status"] == 401
    end
  end

  describe "me/2" do
    test "includes is_superadmin: false for a regular user", %{conn: conn, user: user} do
      authed_conn = Pow.Plug.assign_current_user(conn, user, [])

      resp = get(authed_conn, "/api/me")

      assert %{
               "id" => id,
               "email" => email,
               "account_id" => account_id,
               "role" => _role,
               "is_superadmin" => false
             } = json_response(resp, 200)["data"]

      assert id == user.id
      assert email == user.email
      assert account_id == user.account_id
    end

    test "includes is_superadmin: true for a superadmin (read from the database)", %{
      conn: conn,
      user: user
    } do
      {:ok, _} = Users.set_superadmin(user, true)

      # The assigned struct is STALE (still says false): /api/me must report
      # the database value so grants/revocations apply without re-login.
      refute user.is_superadmin
      authed_conn = Pow.Plug.assign_current_user(conn, user, [])

      resp = get(authed_conn, "/api/me")

      assert %{"is_superadmin" => true} = json_response(resp, 200)["data"]
    end
  end

  describe "delete/2" do
    setup %{conn: conn, user: user} do
      authed_conn = post(conn, Routes.session_path(conn, :create, auth_params(user)))
      :timer.sleep(100)
      {:ok, access_token: authed_conn.private[:api_auth_token]}
    end

    test "invalidates", %{conn: conn, access_token: token} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", token)
        |> delete(Routes.session_path(conn, :delete))

      assert json = json_response(conn, 200)
      assert json["data"] == %{}
    end
  end
end
