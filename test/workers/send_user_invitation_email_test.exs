defmodule ChatApi.Workers.SendUserInvitationEmailTest do
  use ChatApi.DataCase, async: true

  alias ChatApi.InstanceSettings
  alias ChatApi.Workers.SendUserInvitationEmail

  describe "send_user_invitation_email_enabled?/0" do
    setup do
      # Deterministic baseline: no env var, DB state is per-test (sandboxed).
      original = System.get_env("USER_INVITATION_EMAIL_ENABLED")
      System.delete_env("USER_INVITATION_EMAIL_ENABLED")

      on_exit(fn ->
        if original, do: System.put_env("USER_INVITATION_EMAIL_ENABLED", original)
      end)

      :ok
    end

    test "is disabled by default, enabled by a DB override, and clearable" do
      refute SendUserInvitationEmail.send_user_invitation_email_enabled?()

      {:ok, _} = InstanceSettings.set("USER_INVITATION_EMAIL_ENABLED", true)
      assert SendUserInvitationEmail.send_user_invitation_email_enabled?()

      {:ok, _} = InstanceSettings.set("USER_INVITATION_EMAIL_ENABLED", nil)
      refute SendUserInvitationEmail.send_user_invitation_email_enabled?()
    end

    test "still honors the env var when there is no DB row" do
      System.put_env("USER_INVITATION_EMAIL_ENABLED", "1")
      on_exit(fn -> System.delete_env("USER_INVITATION_EMAIL_ENABLED") end)

      assert SendUserInvitationEmail.send_user_invitation_email_enabled?()

      # ...but a DB "false" override wins over the env var.
      {:ok, _} = InstanceSettings.set("USER_INVITATION_EMAIL_ENABLED", false)
      refute SendUserInvitationEmail.send_user_invitation_email_enabled?()
    end
  end
end
