defmodule ChatApiWeb.SecurityIsolationTest do
  @moduledoc """
  Regression tests for the cross-tenant authorization / IDOR fixes.

  Each test authenticates as a user of account A and confirms they cannot
  read, modify, or delete a resource that belongs to a different account B
  (loaded by its raw UUID). Before the fix these controllers loaded the
  resource with a bare `Repo.get!/2` and never checked ownership.
  """
  use ChatApiWeb.ConnCase, async: true

  import ChatApi.Factory
  alias ChatApi.Repo

  setup %{conn: conn} do
    # Attacker: a plain (non-admin) member of their own account A.
    account_a = insert(:account)
    attacker = insert(:user, account: account_a, role: "user")

    # Victim: a separate account B with its own admin.
    account_b = insert(:account)
    victim = insert(:user, account: account_b, role: "admin")

    conn = put_req_header(conn, "accept", "application/json")
    authed = Pow.Plug.assign_current_user(conn, attacker, [])

    {:ok,
     conn: conn,
     authed: authed,
     attacker: attacker,
     account_a: account_a,
     account_b: account_b,
     victim: victim}
  end

  describe "privilege escalation via PUT /api/users/:id/role" do
    test "a plain member cannot promote themselves to admin", %{conn: conn} do
      account = insert(:account)
      member = insert(:user, account: account, role: "user")
      authed = Pow.Plug.assign_current_user(conn, member, [])

      resp = put(authed, "/api/users/#{member.id}/role", %{role: "admin"})

      assert json_response(resp, 401)
      assert Repo.reload(member).role == "user"
    end

    test "an admin can still change roles", %{conn: conn} do
      account = insert(:account)
      admin = insert(:user, account: account, role: "admin")
      target = insert(:user, account: account, role: "user")
      authed = Pow.Plug.assign_current_user(conn, admin, [])

      resp = put(authed, "/api/users/#{target.id}/role", %{role: "admin"})

      assert json_response(resp, 200)
      assert Repo.reload(target).role == "admin"
    end
  end

  describe "personal API keys" do
    test "cannot read another account's key (which would leak its secret value)",
         %{authed: authed, account_b: account_b, victim: victim} do
      key = insert(:personal_api_key, account: account_b, user: victim, value: "super-secret")

      resp = get(authed, "/api/personal_api_keys/#{key.id}")

      assert json_response(resp, 404)
    end

    test "cannot delete another account's key", %{authed: authed, account_b: account_b, victim: victim} do
      key = insert(:personal_api_key, account: account_b, user: victim)

      resp = delete(authed, "/api/personal_api_keys/#{key.id}")

      assert json_response(resp, 404)
      assert Repo.reload(key)
    end
  end

  describe "event subscriptions (webhooks)" do
    test "cannot read another account's subscription", %{authed: authed, account_b: account_b} do
      sub = insert(:event_subscription, account: account_b, webhook_url: "https://victim.example")

      resp = get(authed, "/api/event_subscriptions/#{sub.id}")

      assert json_response(resp, 404)
    end

    test "cannot rewrite another account's webhook_url", %{authed: authed, account_b: account_b} do
      sub = insert(:event_subscription, account: account_b, webhook_url: "https://victim.example")

      resp =
        put(authed, "/api/event_subscriptions/#{sub.id}", %{
          event_subscription: %{webhook_url: "https://attacker.example"}
        })

      assert json_response(resp, 404)
      assert Repo.reload(sub).webhook_url == "https://victim.example"
    end

    test "cannot delete another account's subscription", %{authed: authed, account_b: account_b} do
      sub = insert(:event_subscription, account: account_b)

      resp = delete(authed, "/api/event_subscriptions/#{sub.id}")

      assert json_response(resp, 404)
      assert Repo.reload(sub)
    end
  end

  describe "integration authorizations" do
    test "cannot delete another account's Slack authorization",
         %{authed: authed, account_b: account_b} do
      auth = insert(:slack_authorization, account: account_b)

      resp = delete(authed, "/api/slack/authorizations/#{auth.id}")

      assert json_response(resp, 404)
      assert Repo.reload(auth)
    end

    test "cannot modify another account's Slack settings",
         %{authed: authed, account_b: account_b} do
      auth = insert(:slack_authorization, account: account_b)

      resp =
        post(authed, "/api/slack/authorizations/#{auth.id}/settings", %{
          settings: %{"sync_all_incoming_threads" => true}
        })

      assert json_response(resp, 404)
    end

    test "cannot delete another account's Twilio authorization",
         %{authed: authed, account_b: account_b} do
      auth = insert(:twilio_authorization, account: account_b)

      resp = delete(authed, "/api/twilio/authorizations/#{auth.id}")

      assert json_response(resp, 404)
      assert Repo.reload(auth)
    end

    test "cannot delete another account's Google authorization",
         %{authed: authed, account_b: account_b} do
      auth = insert(:google_authorization, account: account_b)

      resp = delete(authed, "/api/google/authorizations/#{auth.id}")

      assert json_response(resp, 404)
      assert Repo.reload(auth)
    end

    test "cannot delete another account's Github authorization",
         %{authed: authed, account_b: account_b} do
      auth = insert(:github_authorization, account: account_b)

      resp = delete(authed, "/api/github/authorizations/#{auth.id}")

      assert json_response(resp, 404)
      assert Repo.reload(auth)
    end
  end

  describe "browser sessions" do
    test "cannot update another account's session", %{authed: authed, account_b: account_b} do
      session = insert(:browser_session, account: account_b)

      resp =
        put(authed, "/api/browser_sessions/#{session.id}", %{
          browser_session: %{metadata: %{"tampered" => true}}
        })

      assert json_response(resp, 404)
    end

    test "cannot delete another account's session", %{authed: authed, account_b: account_b} do
      session = insert(:browser_session, account: account_b)

      resp = delete(authed, "/api/browser_sessions/#{session.id}")

      assert json_response(resp, 404)
      assert Repo.reload(session)
    end
  end

  describe "user invitations" do
    test "cannot delete another account's invitation", %{authed: authed, account_b: account_b} do
      invite = insert(:user_invitation, account: account_b)

      resp = delete(authed, "/api/user_invitations/#{invite.id}")

      # A plain member is blocked by the admin guard (401); an admin of A would
      # get 404 from the account-scoping. Either way the invite survives.
      assert resp.status in [401, 404]
      assert Repo.reload(invite)
    end
  end

  describe "email account credential redaction" do
    test "inspecting an email account never exposes the plaintext passwords" do
      email_account =
        build(:email_account,
          imap_password: "super-secret-imap-pw",
          smtp_password: "super-secret-smtp-pw"
        )

      dump = inspect(email_account)

      refute dump =~ "super-secret-imap-pw"
      refute dump =~ "super-secret-smtp-pw"
    end
  end

  describe "message injection across tenants" do
    test "cannot post a message into another account's conversation",
         %{authed: authed, account_b: account_b} do
      conversation = insert(:conversation, account: account_b)

      resp =
        post(authed, "/api/messages", %{
          message: %{body: "injected", conversation_id: conversation.id}
        })

      assert json_response(resp, 403)
      assert Repo.all(Ecto.assoc(conversation, :messages)) == []
    end
  end
end
