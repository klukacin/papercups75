defmodule ChatApiWeb.RegistrationControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory
  alias ChatApi.{Accounts, Repo, UserInvitations}

  @password "secret1234"

  describe "create/2" do
    @valid_params %{
      "user" => %{
        "company_name" => "Papercups",
        "email" => "test@example.com",
        "password" => @password,
        "password_confirmation" => @password
      }
    }

    @invalid_params %{
      "user" => %{
        "email" => "invalid",
        "password" => @password,
        "password_confirmation" => "",
        "company_name" => "Invalid Inc"
      }
    }

    @missing_company_name %{
      "user" => %{
        "email" => "invalid",
        "password" => @password,
        "password_confirmation" => @password,
        "company_name" => ""
      }
    }

    test "with valid params", %{conn: conn} do
      conn = post(conn, Routes.registration_path(conn, :create, @valid_params))

      assert json = json_response(conn, 200)
      assert json["data"]["token"]
      assert json["data"]["renew_token"]
    end

    test "with invalid params", %{conn: conn} do
      conn =
        post(
          conn,
          Routes.registration_path(conn, :create, @invalid_params)
        )

      assert json = json_response(conn, 500)
      assert json["error"]["message"] == "Couldn't create user"
      assert json["error"]["status"] == 500
      assert json["error"]["errors"]["password_confirmation"] == ["does not match confirmation"]
      assert json["error"]["errors"]["email"] == ["has invalid format"]

      # No accounts should have been created
      assert [] = Accounts.list_accounts()
    end

    test "with missing company name", %{conn: conn} do
      conn = post(conn, Routes.registration_path(conn, :create, @missing_company_name))

      assert json = json_response(conn, 500)
      assert json["error"]["message"] == "Couldn't create user"
      assert json["error"]["status"] == 500
      assert json["error"]["errors"]["company_name"] == ["can't be blank"]

      # No accounts should have been created
      assert [] = Accounts.list_accounts()
    end
  end

  describe("registering with invitation token") do
    setup %{conn: conn} do
      account = insert(:account)
      admin_user = insert(:user, account: account, role: "admin")

      # conn = put_req_header(conn, "accept", "application/json")
      authed_conn = Pow.Plug.assign_current_user(conn, admin_user, [])

      {:ok, authed_conn: authed_conn, account: account, user: admin_user}
    end

    test "create with existing user",
         %{conn: conn, authed_conn: authed_conn, account: account} do
      existing_conn =
        post(authed_conn, Routes.user_invitation_path(authed_conn, :create),
          user_invitation: %{account_id: account.id}
        )

      invite_token = json_response(existing_conn, 201)["data"]["id"]

      random_number = :rand.uniform(1_000_000_000) |> Integer.to_string()
      registration_email = random_number <> "anotheremail@example.com"

      params = %{
        "user" => %{
          "invite_token" => invite_token,
          "email" => registration_email,
          "password" => @password,
          "password_confirmation" => @password
        }
      }

      post(conn, Routes.registration_path(conn, :create, params))
      account = Accounts.get_account!(account.id) |> Repo.preload([:users])

      assert(Enum.any?(account.users, fn u -> u.email == registration_email end))
    end

    # Regression: Pow.Plug.create_user bypasses Users.create_user/1 and its
    # account_users membership mirror, so freshly registered users used to get
    # 403 ("not a member of this account") from CurrentAccountPlug on every
    # protected route (observed in production).
    test "a freshly registered user can access protected routes", %{conn: conn} do
      params = %{
        "user" => %{
          "company_name" => "Membership Test Co",
          "email" => "membership-test@example.com",
          "password" => @password,
          "password_confirmation" => @password
        }
      }

      registration = post(conn, Routes.registration_path(conn, :create, params))
      assert token = json_response(registration, 200)["data"]["token"]

      me =
        build_conn()
        |> put_req_header("authorization", token)
        |> get("/api/me")

      assert %{"email" => "membership-test@example.com"} = json_response(me, 200)["data"]
    end

    # Regression: the invite path used to run Pow.Plug.create_user twice (a
    # leftover duplicated block), so the happy path returned a 500
    # ("Couldn't create user") even though the user WAS created - and the user
    # had no account_users membership either.
    test "invite registration returns 200 and the user can access protected routes",
         %{conn: conn, account: account} do
      {:ok, invite} = UserInvitations.create_user_invitation(%{account_id: account.id})

      email = "invited-member-#{:rand.uniform(1_000_000_000)}@example.com"

      params = %{
        "user" => %{
          "invite_token" => invite.id,
          "email" => email,
          "password" => @password,
          "password_confirmation" => @password
        }
      }

      registration = post(conn, Routes.registration_path(conn, :create, params))
      assert token = json_response(registration, 200)["data"]["token"]

      me =
        build_conn()
        |> put_req_header("authorization", token)
        |> get("/api/me")

      assert %{"email" => ^email} = json_response(me, 200)["data"]
    end

    test "error for non-existing invite token", %{conn: conn} do
      random_number =
        :rand.uniform(1_000_000_000)
        |> Integer.to_string()

      registration_email = random_number <> "anotheremail@example.com"

      params = %{
        "user" => %{
          "invite_token" => "093ada1d-02c2-4e08-bdd1-d0d6e567db2e",
          "email" => registration_email,
          "password" => @password,
          "password_confirmation" => @password
        }
      }

      existing_conn = post(conn, Routes.registration_path(conn, :create, params))
      assert json = json_response(existing_conn, 403)
      assert json["error"]["message"] == "Invalid invitation token"
      assert json["error"]["status"] == 403
    end

    test "error for expired invite token", %{conn: conn, account: account} do
      {:ok, user_invitation} = UserInvitations.create_user_invitation(%{account_id: account.id})
      UserInvitations.expire_user_invitation(user_invitation)

      random_number =
        :rand.uniform(1_000_000_000)
        |> Integer.to_string()

      registration_email = random_number <> "anotheremail@example.com"

      params = %{
        "user" => %{
          "invite_token" => user_invitation.id,
          "email" => registration_email,
          "password" => @password,
          "password_confirmation" => @password
        }
      }

      existing_conn = post(conn, Routes.registration_path(conn, :create, params))
      assert json = json_response(existing_conn, 403)
      assert json["error"]["message"] == "Invitation token has expired"
      assert json["error"]["status"] == 403
    end
  end
end
