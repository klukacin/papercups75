defmodule ChatApiWeb.AdminSettingsControllerTest do
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory

  alias ChatApi.InstanceSettings

  setup %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")
    superadmin = insert(:user, is_superadmin: true)

    {:ok, conn: conn, authed_conn: Pow.Plug.assign_current_user(conn, superadmin, [])}
  end

  # JSON booleans/nulls must survive the round trip, so send a raw JSON body
  # (map params in ConnTest are form-encoded, which stringifies everything).
  defp put_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(body))
  end

  defp put_env(key, value) do
    original = System.get_env(key)
    System.put_env(key, value)
    on_exit(fn -> restore_env(key, original) end)
  end

  defp delete_env(key) do
    original = System.get_env(key)
    System.delete_env(key)
    on_exit(fn -> restore_env(key, original) end)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp editable_by_key(json) do
    Map.new(json["data"]["editable"], &{&1["key"], &1})
  end

  describe "GET /api/admin/settings" do
    test "returns editable settings and the masked env-only report", %{authed_conn: authed_conn} do
      put_env("REACT_APP_ADMIN_INBOX_ID", "inbox-from-env")

      json = authed_conn |> get("/api/admin/settings") |> json_response(200)

      editable = json["data"]["editable"]
      env_only = json["data"]["env_only"]

      assert length(editable) == 16
      assert length(env_only) == 10

      by_key = editable_by_key(json)

      assert %{"type" => "boolean", "source" => _, "value" => _} =
               by_key["PAPERCUPS_REGISTRATION_DISABLED"]

      assert %{"type" => "string", "value" => "inbox-from-env", "source" => "env"} =
               by_key["REACT_APP_ADMIN_INBOX_ID"]

      env_only_keys = Enum.map(env_only, & &1["key"])
      assert "SECRET_KEY_BASE" in env_only_keys
      assert "DATABASE_URL" in env_only_keys

      for entry <- env_only do
        assert is_boolean(entry["is_set"])
        assert Map.has_key?(entry, "preview")
      end
    end

    test "the env-only report never contains a full secret", %{authed_conn: authed_conn} do
      secret = "fake-stripe-secret-value-123456"
      put_env("PAPERCUPS_STRIPE_SECRET", secret)

      resp = get(authed_conn, "/api/admin/settings")
      body = response(resp, 200)

      refute body =~ secret

      by_key =
        resp
        |> json_response(200)
        |> Map.fetch!("data")
        |> Map.fetch!("env_only")
        |> Map.new(&{&1["key"], &1})

      assert %{"is_set" => true, "preview" => "fake…"} = by_key["PAPERCUPS_STRIPE_SECRET"]
    end

    test "a regular user gets 403 (workspace admins included)", %{conn: conn} do
      admin = insert(:user, role: "admin")
      authed_conn = Pow.Plug.assign_current_user(conn, admin, [])

      resp = get(authed_conn, "/api/admin/settings")

      assert %{"status" => 403} = json_response(resp, 403)["error"]
    end

    test "an unauthenticated request returns 401", %{conn: conn} do
      assert conn |> get("/api/admin/settings") |> Map.fetch!(:status) == 401
    end
  end

  describe "PUT /api/admin/settings" do
    test "sets and clears an override (roundtrip back to env fallback)", %{
      authed_conn: authed_conn
    } do
      delete_env("REACT_APP_URL")

      json =
        authed_conn
        |> put_json("/api/admin/settings", %{
          "settings" => %{"REACT_APP_URL" => "https://chat.example.com"}
        })
        |> json_response(200)

      assert %{"value" => "https://chat.example.com", "source" => "override"} =
               editable_by_key(json)["REACT_APP_URL"]

      # A fresh GET agrees (the override is persisted).
      json = authed_conn |> get("/api/admin/settings") |> json_response(200)

      assert %{"value" => "https://chat.example.com", "source" => "override"} =
               editable_by_key(json)["REACT_APP_URL"]

      # null clears the override; with no env var the value drops to nil.
      json =
        authed_conn
        |> put_json("/api/admin/settings", %{"settings" => %{"REACT_APP_URL" => nil}})
        |> json_response(200)

      assert %{"value" => nil, "source" => nil} = editable_by_key(json)["REACT_APP_URL"]
    end

    test "clearing an override falls back to the env var", %{authed_conn: authed_conn} do
      put_env("REACT_APP_POSTHOG_API_HOST", "https://posthog.env.example.com")

      json =
        authed_conn
        |> put_json("/api/admin/settings", %{
          "settings" => %{"REACT_APP_POSTHOG_API_HOST" => "https://posthog.db.example.com"}
        })
        |> json_response(200)

      assert %{"value" => "https://posthog.db.example.com", "source" => "override"} =
               editable_by_key(json)["REACT_APP_POSTHOG_API_HOST"]

      json =
        authed_conn
        |> put_json("/api/admin/settings", %{
          "settings" => %{"REACT_APP_POSTHOG_API_HOST" => nil}
        })
        |> json_response(200)

      assert %{"value" => "https://posthog.env.example.com", "source" => "env"} =
               editable_by_key(json)["REACT_APP_POSTHOG_API_HOST"]
    end

    test "normalizes JSON booleans to \"true\"/\"false\" strings", %{authed_conn: authed_conn} do
      json =
        authed_conn
        |> put_json("/api/admin/settings", %{
          "settings" => %{
            "REACT_APP_FILE_UPLOADS_ENABLED" => true,
            "REACT_APP_DEBUG_MODE_ENABLED" => false
          }
        })
        |> json_response(200)

      by_key = editable_by_key(json)

      assert %{"value" => "true", "source" => "override"} =
               by_key["REACT_APP_FILE_UPLOADS_ENABLED"]

      assert %{"value" => "false", "source" => "override"} =
               by_key["REACT_APP_DEBUG_MODE_ENABLED"]
    end

    test "an unknown key returns 422 naming the offender and applies nothing", %{
      authed_conn: authed_conn
    } do
      delete_env("REACT_APP_URL")

      resp =
        put_json(authed_conn, "/api/admin/settings", %{
          "settings" => %{
            "REACT_APP_URL" => "https://should-not-apply.example.com",
            "TOTALLY_BOGUS_KEY" => "nope"
          }
        })

      assert %{"status" => 422, "message" => message} = json_response(resp, 422)["error"]
      assert message =~ "TOTALLY_BOGUS_KEY"

      # All-or-nothing: the valid key in the same request was not applied.
      json = authed_conn |> get("/api/admin/settings") |> json_response(200)
      assert %{"value" => nil, "source" => nil} = editable_by_key(json)["REACT_APP_URL"]
    end

    test "a request without a settings object returns 422", %{authed_conn: authed_conn} do
      resp = put_json(authed_conn, "/api/admin/settings", %{"nope" => true})

      assert %{"status" => 422} = json_response(resp, 422)["error"]
    end

    test "a regular user gets 403 and nothing is applied", %{conn: conn} do
      admin = insert(:user, role: "admin")
      authed_conn = Pow.Plug.assign_current_user(conn, admin, [])

      resp =
        put_json(authed_conn, "/api/admin/settings", %{
          "settings" => %{"REACT_APP_URL" => "https://hax.example.com"}
        })

      assert %{"status" => 403} = json_response(resp, 403)["error"]
      assert ChatApi.Repo.aggregate(InstanceSettings.Setting, :count) == 0
    end

    test "an unauthenticated request returns 401", %{conn: conn} do
      resp =
        put_json(conn, "/api/admin/settings", %{
          "settings" => %{"REACT_APP_URL" => "https://hax.example.com"}
        })

      assert resp.status == 401
    end
  end

  describe "registration honors the DB override" do
    @registration_params %{
      "user" => %{
        "company_name" => "Setting Testers Inc",
        "email" => "settings-registration@example.com",
        "password" => "secret1234",
        "password_confirmation" => "secret1234"
      }
    }

    test "disabling registration via the API blocks invite-less signup; clearing restores it",
         %{conn: conn, authed_conn: authed_conn} do
      resp =
        put_json(authed_conn, "/api/admin/settings", %{
          "settings" => %{"PAPERCUPS_REGISTRATION_DISABLED" => true}
        })

      assert json_response(resp, 200)

      resp = post(conn, "/api/registration", @registration_params)
      assert %{"status" => 403, "message" => message} = json_response(resp, 403)["error"]
      assert message =~ "invitation token is required"

      # Clear the override -> registration works again.
      resp =
        put_json(authed_conn, "/api/admin/settings", %{
          "settings" => %{"PAPERCUPS_REGISTRATION_DISABLED" => nil}
        })

      assert json_response(resp, 200)

      resp = post(conn, "/api/registration", @registration_params)
      assert json_response(resp, 200)["data"]["token"]
    end
  end
end
