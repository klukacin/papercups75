defmodule ChatApi.InstanceSettingsTest do
  use ChatApi.DataCase, async: true

  alias ChatApi.InstanceSettings
  alias ChatApi.InstanceSettings.Setting

  # NB: DB overrides are sandboxed per test, but System.put_env/2 mutates
  # process-global state. Every mutation goes through put_env/2 / delete_env/1
  # below (which restore the original value on exit), and the env vars touched
  # here are not read by any other test file, so async: true stays safe.

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

  describe "get/1" do
    test "returns nil when neither a DB row nor an env var exists" do
      delete_env("REACT_APP_LOGROCKET_ID")

      assert InstanceSettings.get("REACT_APP_LOGROCKET_ID") == nil
    end

    test "falls back to the env var when there is no DB row" do
      put_env("REACT_APP_LOGROCKET_ID", "env-logrocket")

      assert InstanceSettings.get("REACT_APP_LOGROCKET_ID") == "env-logrocket"
    end

    test "prefers the DB override over the env var" do
      put_env("REACT_APP_LOGROCKET_ID", "env-logrocket")
      {:ok, _} = InstanceSettings.set("REACT_APP_LOGROCKET_ID", "db-logrocket")

      assert InstanceSettings.get("REACT_APP_LOGROCKET_ID") == "db-logrocket"
    end

    test "raises on a key outside the whitelist" do
      assert_raise ArgumentError, ~r/TOTALLY_UNKNOWN_KEY/, fn ->
        InstanceSettings.get("TOTALLY_UNKNOWN_KEY")
      end
    end
  end

  describe "set/2" do
    test "upserts: the second write replaces the first (single row per key)" do
      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", "first")
      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", "second")

      assert InstanceSettings.get("REACT_APP_SENTRY_DSN") == "second"
      assert Repo.aggregate(Setting, :count) == 1
    end

    test "setting nil deletes the row and restores the env fallback" do
      put_env("REACT_APP_SENTRY_DSN", "env-dsn")
      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", "db-dsn")
      assert InstanceSettings.get("REACT_APP_SENTRY_DSN") == "db-dsn"

      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", nil)

      assert InstanceSettings.get("REACT_APP_SENTRY_DSN") == "env-dsn"
      assert Repo.aggregate(Setting, :count) == 0
    end

    test "setting an empty string also deletes the row" do
      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", "db-dsn")
      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", "")

      assert Repo.aggregate(Setting, :count) == 0
    end

    test "clearing a key that has no row is a no-op success" do
      assert {:ok, nil} = InstanceSettings.set("REACT_APP_SENTRY_DSN", nil)
    end

    test "normalizes booleans to \"true\"/\"false\" strings" do
      {:ok, _} = InstanceSettings.set("PAPERCUPS_REGISTRATION_DISABLED", true)
      assert InstanceSettings.get("PAPERCUPS_REGISTRATION_DISABLED") == "true"

      {:ok, _} = InstanceSettings.set("PAPERCUPS_REGISTRATION_DISABLED", false)
      assert InstanceSettings.get("PAPERCUPS_REGISTRATION_DISABLED") == "false"
    end

    test "rejects keys outside the whitelist" do
      assert {:error, :unknown_key} = InstanceSettings.set("TOTALLY_UNKNOWN_KEY", "value")
      assert Repo.aggregate(Setting, :count) == 0
    end
  end

  describe "enabled?/1" do
    test "\"1\" and \"true\" are truthy; anything else is falsy" do
      delete_env("REACT_APP_STORYTIME_ENABLED")
      refute InstanceSettings.enabled?("REACT_APP_STORYTIME_ENABLED")

      for truthy <- ["1", "true"] do
        {:ok, _} = InstanceSettings.set("REACT_APP_STORYTIME_ENABLED", truthy)
        assert InstanceSettings.enabled?("REACT_APP_STORYTIME_ENABLED")
      end

      for falsy <- ["0", "false", "yes", "TRUE"] do
        {:ok, _} = InstanceSettings.set("REACT_APP_STORYTIME_ENABLED", falsy)
        refute InstanceSettings.enabled?("REACT_APP_STORYTIME_ENABLED")
      end
    end

    test "falls back to the env var when there is no DB row" do
      put_env("REACT_APP_STORYTIME_ENABLED", "1")
      assert InstanceSettings.enabled?("REACT_APP_STORYTIME_ENABLED")
    end

    test "a DB \"false\" override wins over a truthy env var" do
      put_env("REACT_APP_STORYTIME_ENABLED", "true")
      {:ok, _} = InstanceSettings.set("REACT_APP_STORYTIME_ENABLED", false)

      refute InstanceSettings.enabled?("REACT_APP_STORYTIME_ENABLED")
    end

    test "raises on a key outside the whitelist" do
      assert_raise ArgumentError, fn -> InstanceSettings.enabled?("NOT_A_SETTING") end
    end
  end

  describe "update_settings/1" do
    test "applies multiple keys at once" do
      assert :ok =
               InstanceSettings.update_settings(%{
                 "REACT_APP_URL" => "https://chat.example.com",
                 "REACT_APP_EU_EDITION" => true
               })

      assert InstanceSettings.get("REACT_APP_URL") == "https://chat.example.com"
      assert InstanceSettings.get("REACT_APP_EU_EDITION") == "true"
    end

    test "rejects the whole batch when any key is unknown" do
      assert {:error, {:unknown_keys, ["BOGUS_KEY"]}} =
               InstanceSettings.update_settings(%{
                 "REACT_APP_URL" => "https://chat.example.com",
                 "BOGUS_KEY" => "nope"
               })

      # Nothing was applied (all-or-nothing).
      assert Repo.aggregate(Setting, :count) == 0
    end

    test "rejects non-scalar values" do
      assert {:error, {:invalid_values, ["REACT_APP_URL"]}} =
               InstanceSettings.update_settings(%{"REACT_APP_URL" => %{"nested" => "map"}})

      assert Repo.aggregate(Setting, :count) == 0
    end
  end

  describe "editable_settings/0" do
    test "covers the full whitelist with key, type, value and source" do
      settings = InstanceSettings.editable_settings()
      keys = Enum.map(settings, & &1.key)

      assert length(settings) == 16
      assert keys == InstanceSettings.editable_keys()

      for expected <- [
            "PAPERCUPS_REGISTRATION_DISABLED",
            "USER_INVITATION_EMAIL_ENABLED",
            "REACT_APP_FILE_UPLOADS_ENABLED",
            "REACT_APP_STORYTIME_ENABLED",
            "REACT_APP_EU_EDITION",
            "REACT_APP_DEBUG_MODE_ENABLED",
            "REACT_APP_URL",
            "REACT_APP_STRIPE_PUBLIC_KEY",
            "REACT_APP_SENTRY_DSN",
            "REACT_APP_LOGROCKET_ID",
            "REACT_APP_POSTHOG_TOKEN",
            "REACT_APP_POSTHOG_API_HOST",
            "REACT_APP_SLACK_CLIENT_ID",
            "REACT_APP_GITHUB_APP_NAME",
            "REACT_APP_ADMIN_ACCOUNT_ID",
            "REACT_APP_ADMIN_INBOX_ID"
          ] do
        assert expected in keys
      end

      by_key = Map.new(settings, &{&1.key, &1})
      assert by_key["PAPERCUPS_REGISTRATION_DISABLED"].type == :boolean
      assert by_key["REACT_APP_URL"].type == :string
    end

    test "reports the source as override > env > nil" do
      delete_env("REACT_APP_LOGROCKET_ID")
      put_env("REACT_APP_SENTRY_DSN", "env-dsn")
      {:ok, _} = InstanceSettings.set("REACT_APP_EU_EDITION", true)

      by_key = Map.new(InstanceSettings.editable_settings(), &{&1.key, &1})

      assert %{value: nil, source: nil} = by_key["REACT_APP_LOGROCKET_ID"]
      assert %{value: "env-dsn", source: "env"} = by_key["REACT_APP_SENTRY_DSN"]
      assert %{value: "true", source: "override"} = by_key["REACT_APP_EU_EDITION"]
    end

    test "a DB override shadows the env var in the report" do
      put_env("REACT_APP_SENTRY_DSN", "env-dsn")
      {:ok, _} = InstanceSettings.set("REACT_APP_SENTRY_DSN", "db-dsn")

      by_key = Map.new(InstanceSettings.editable_settings(), &{&1.key, &1})

      assert %{value: "db-dsn", source: "override"} = by_key["REACT_APP_SENTRY_DSN"]
    end
  end

  describe "resolve_all/0" do
    test "resolves every whitelisted key with db > env > nil precedence" do
      delete_env("REACT_APP_LOGROCKET_ID")
      put_env("REACT_APP_SENTRY_DSN", "env-dsn")
      put_env("REACT_APP_EU_EDITION", "false")
      {:ok, _} = InstanceSettings.set("REACT_APP_EU_EDITION", true)

      resolved = InstanceSettings.resolve_all()

      assert map_size(resolved) == 16
      assert resolved["REACT_APP_LOGROCKET_ID"] == nil
      assert resolved["REACT_APP_SENTRY_DSN"] == "env-dsn"
      assert resolved["REACT_APP_EU_EDITION"] == "true"
    end
  end

  describe "env_only_status/0" do
    @env_only_keys [
      "DATABASE_URL",
      "SECRET_KEY_BASE",
      "BACKEND_URL",
      "REDIS_URL",
      "REDIS_TLS_URL",
      "MAILER_ADAPTER",
      "AWS_ACCESS_KEY_ID",
      "AWS_REGION",
      "BUCKET_NAME",
      "PAPERCUPS_STRIPE_SECRET"
    ]

    test "reports every boot-critical key" do
      assert Enum.map(InstanceSettings.env_only_status(), & &1.key) == @env_only_keys
    end

    test "masks set values to at most 4 chars and never leaks the full secret" do
      secret = "ecto://admin:hunter2-password@db.internal:5432/papercups"
      put_env("DATABASE_URL", secret)
      delete_env("MAILER_ADAPTER")

      status = InstanceSettings.env_only_status()
      by_key = Map.new(status, &{&1.key, &1})

      assert %{is_set: true, preview: "ecto…"} = by_key["DATABASE_URL"]
      assert %{is_set: false, preview: nil} = by_key["MAILER_ADAPTER"]

      # The full secret must never appear anywhere in the report (nor in its
      # JSON encoding, which is what the admin API ships to the browser).
      refute inspect(status) =~ secret
      refute inspect(status) =~ "hunter2"
      refute Jason.encode!(status) =~ secret
      refute Jason.encode!(status) =~ "hunter2"
    end

    test "short values are still truncated with an ellipsis" do
      put_env("SECRET_KEY_BASE", "abcdefgh")

      by_key = Map.new(InstanceSettings.env_only_status(), &{&1.key, &1})

      assert by_key["SECRET_KEY_BASE"].preview == "abcd…"
    end

    test "env-only keys are not editable" do
      assert {:error, :unknown_key} = InstanceSettings.set("SECRET_KEY_BASE", "oops")
      assert_raise ArgumentError, fn -> InstanceSettings.get("SECRET_KEY_BASE") end
    end
  end
end
