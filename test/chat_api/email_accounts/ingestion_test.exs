defmodule ChatApi.EmailAccounts.IngestionTest do
  use ChatApi.DataCase
  use Oban.Testing, repo: ChatApi.Repo

  import ChatApi.Factory
  import Mock

  alias ChatApi.{Conversations, Customers, Messages}
  alias ChatApi.EmailAccounts.Ingestion
  alias ChatApi.Messages.Message
  alias ChatApi.Workers.SendEmailAccountReply

  @fixtures Path.expand("../../fixtures/email", __DIR__)

  setup do
    account = insert(:account, company_name: "Test Co")
    inbox = insert(:inbox, account: account)
    agent = insert(:user, account: account, email: "agent@company.test")

    email_account =
      insert(:email_account,
        account: account,
        inbox: inbox,
        from_address: "support@company.test",
        imap_username: "imap-login@company.test"
      )

    {:ok, account: account, inbox: inbox, agent: agent, email_account: email_account}
  end

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp raw_email(headers, body) do
    header_lines = Enum.map(headers, fn {name, value} -> "#{name}: #{value}" end)

    Enum.join(header_lines ++ ["", body], "\r\n")
  end

  defp count_messages(account_id),
    do: Message |> where(account_id: ^account_id) |> Repo.aggregate(:count)

  defp count_conversations(account_id) do
    ChatApi.Conversations.Conversation
    |> where(account_id: ^account_id)
    |> Repo.aggregate(:count)
  end

  describe "process_raw_email/2 — new conversations" do
    test "creates a customer, conversation and message with email_* metadata", ctx do
      assert {:ok, %Message{} = created} =
               Ingestion.process_raw_email(fixture("simple.eml"), ctx.email_account)

      message = Messages.get_message!(created.id)

      assert message.body =~ "Hello, I cannot log in to my account"
      assert message.source == "email"
      assert message.user_id == nil
      assert message.customer.email == "jane@customer.test"
      assert message.sent_at == ~U[2026-07-10 10:30:00Z]

      # The customer was created in the right workspace
      assert %{account_id: account_id} =
               Customers.find_by_email("jane@customer.test", ctx.account.id)

      assert account_id == ctx.account.id

      conversation = Conversations.get_conversation!(message.conversation_id)
      assert conversation.source == "email"
      assert conversation.subject == "Need help with my account"
      assert conversation.inbox_id == ctx.inbox.id
      assert conversation.customer_id == message.customer_id
      assert conversation.status == "open"

      email_account_id = ctx.email_account.id

      assert %{
               "email_message_id" => "<simple-001@customer.test>",
               "email_in_reply_to" => nil,
               "email_references" => nil,
               "email_subject" => "Need help with my account",
               "email_from" => "jane@customer.test",
               "email_to" => ["support@company.test"],
               "email_account_id" => ^email_account_id
             } = message.metadata
    end

    test "a failing attachment upload does not fail the message", ctx do
      # No AWS/S3 is configured in tests, so the attachment upload fails —
      # the message must still be created (attachment errors are logged).
      assert {:ok, %Message{} = created} =
               Ingestion.process_raw_email(fixture("multipart_attachment.eml"), ctx.email_account)

      message = Messages.get_message!(created.id)
      assert message.body == "Please find the invoice attached."
      assert message.attachments == []
      assert message.metadata["email_message_id"] == "<multipart-001@customer.test>"
    end
  end

  describe "process_raw_email/2 — sender resolution" do
    test "creates an agent message when From matches a workspace user", ctx do
      conversation = insert_email_conversation(ctx)
      insert_thread_anchor(ctx, conversation)

      raw =
        raw_email(
          [
            {"Message-ID", "<agent-001@company.test>"},
            {"From", "Agent <agent@company.test>"},
            {"To", "Jane Customer <jane@customer.test>"},
            {"Cc", "support@company.test"},
            {"Subject", "Re: Need help with my account"},
            {"References", "<outbound-001@company.test>"}
          ],
          "Agent replying from their own mail client."
        )

      assert {:ok, %Message{} = created} = Ingestion.process_raw_email(raw, ctx.email_account)

      message = Messages.get_message!(created.id)
      assert message.conversation_id == conversation.id
      assert message.user_id == ctx.agent.id
      assert message.customer_id == nil
      # The counterparty (not the agent) is recorded as the reply-to address
      assert message.metadata["email_from"] == "jane@customer.test"
    end

    test "a user from another workspace is treated as a customer", ctx do
      insert(:user, email: "other-workspace@example.test")

      raw =
        raw_email(
          [
            {"Message-ID", "<other-ws-001@example.test>"},
            {"From", "other-workspace@example.test"},
            {"To", "support@company.test"},
            {"Subject", "Hello"}
          ],
          "I look like an agent but in another workspace."
        )

      assert {:ok, %Message{} = message} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert message.user_id == nil
      assert %{email: "other-workspace@example.test"} = Repo.preload(message, :customer).customer
    end
  end

  describe "process_raw_email/2 — threading" do
    test "threads onto the conversation whose message the References point at", ctx do
      conversation = insert_email_conversation(ctx)
      insert_thread_anchor(ctx, conversation)

      assert {:ok, %Message{} = message} =
               Ingestion.process_raw_email(
                 fixture("reply_with_references.eml"),
                 ctx.email_account
               )

      assert message.conversation_id == conversation.id
      assert message.metadata["email_in_reply_to"] == "<outbound-001@company.test>"

      # References keep their original (oldest → newest) header order
      assert message.metadata["email_references"] ==
               "<simple-001@customer.test> <outbound-001@company.test>"

      # No extra conversation was created
      assert count_conversations(ctx.account.id) == 1
    end

    test "References threading also matches (and reopens) closed conversations", ctx do
      conversation = insert_email_conversation(ctx, status: "closed")
      insert_thread_anchor(ctx, conversation)

      assert {:ok, %Message{} = message} =
               Ingestion.process_raw_email(
                 fixture("reply_with_references.eml"),
                 ctx.email_account
               )

      assert message.conversation_id == conversation.id
      # A customer reply reopens the conversation (post-creation hooks)
      assert Conversations.get_conversation!(conversation.id).status == "open"
    end

    test "falls back to subject threading on an open conversation with the same customer",
         ctx do
      customer = insert(:customer, account: ctx.account, email: "jane@customer.test")

      conversation =
        insert_email_conversation(ctx, customer: customer, subject: "Need help with my account")

      raw =
        raw_email(
          [
            {"Message-ID", "<subject-001@customer.test>"},
            {"From", "jane@customer.test"},
            {"To", "support@company.test"},
            {"Subject", "Re: Need help with my account"}
          ],
          "Following up — any news?"
        )

      assert {:ok, %Message{} = message} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert message.conversation_id == conversation.id
      assert count_conversations(ctx.account.id) == 1
    end

    test "subject threading ignores closed conversations", ctx do
      customer = insert(:customer, account: ctx.account, email: "jane@customer.test")

      closed =
        insert_email_conversation(ctx,
          customer: customer,
          subject: "Need help with my account",
          status: "closed"
        )

      raw =
        raw_email(
          [
            {"Message-ID", "<subject-002@customer.test>"},
            {"From", "jane@customer.test"},
            {"To", "support@company.test"},
            {"Subject", "Re: Need help with my account"}
          ],
          "New thread please."
        )

      assert {:ok, %Message{} = message} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert message.conversation_id != closed.id
      assert Conversations.get_conversation!(closed.id).status == "closed"
      assert count_conversations(ctx.account.id) == 2
    end

    test "subject threading requires the same customer and the same inbox", ctx do
      other_customer = insert(:customer, account: ctx.account, email: "someone-else@x.test")

      other_customers_conversation =
        insert_email_conversation(ctx,
          customer: other_customer,
          subject: "Need help with my account"
        )

      other_inbox = insert(:inbox, account: ctx.account)
      jane = insert(:customer, account: ctx.account, email: "jane@customer.test")

      other_inbox_conversation =
        insert(:conversation,
          account: ctx.account,
          inbox: other_inbox,
          customer: jane,
          source: "email",
          status: "open",
          subject: "Need help with my account"
        )

      raw =
        raw_email(
          [
            {"Message-ID", "<subject-003@customer.test>"},
            {"From", "jane@customer.test"},
            {"To", "support@company.test"},
            {"Subject", "Need help with my account"}
          ],
          "Should start a fresh conversation."
        )

      assert {:ok, %Message{} = message} = Ingestion.process_raw_email(raw, ctx.email_account)

      refute message.conversation_id in [
               other_customers_conversation.id,
               other_inbox_conversation.id
             ]

      assert count_conversations(ctx.account.id) == 3
    end

    test "emails without a subject never subject-thread", ctx do
      customer = insert(:customer, account: ctx.account, email: "jane@customer.test")
      insert_email_conversation(ctx, customer: customer, subject: nil)

      raw =
        raw_email(
          [
            {"Message-ID", "<no-subject-001@customer.test>"},
            {"From", "jane@customer.test"},
            {"To", "support@company.test"}
          ],
          "No subject here."
        )

      assert {:ok, %Message{} = message} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert count_conversations(ctx.account.id) == 2
      assert Conversations.get_conversation!(message.conversation_id).subject == nil
    end
  end

  describe "process_raw_email/2 — dedup" do
    test "the same Message-ID is only ingested once per workspace", ctx do
      assert {:ok, %Message{}} =
               Ingestion.process_raw_email(fixture("simple.eml"), ctx.email_account)

      assert {:ok, :duplicate} =
               Ingestion.process_raw_email(fixture("simple.eml"), ctx.email_account)

      assert count_messages(ctx.account.id) == 1
      assert count_conversations(ctx.account.id) == 1
    end

    test "dedup is scoped to the workspace", ctx do
      assert {:ok, %Message{}} =
               Ingestion.process_raw_email(fixture("simple.eml"), ctx.email_account)

      other_account = insert(:account)
      other_inbox = insert(:inbox, account: other_account)

      other_email_account =
        insert(:email_account,
          account: other_account,
          inbox: other_inbox,
          from_address: "help@other.test",
          imap_username: "help@other.test"
        )

      assert {:ok, %Message{}} =
               Ingestion.process_raw_email(fixture("simple.eml"), other_email_account)

      assert count_messages(ctx.account.id) == 1
      assert count_messages(other_account.id) == 1
    end
  end

  describe "process_raw_email/2 — loop/abuse guards" do
    test "skips Auto-Submitted auto-replies", ctx do
      assert {:ok, :skipped} =
               Ingestion.process_raw_email(fixture("auto_submitted.eml"), ctx.email_account)

      assert_nothing_created(ctx)
    end

    test "skips Precedence: bulk mail", ctx do
      assert {:ok, :skipped} =
               Ingestion.process_raw_email(fixture("bulk_precedence.eml"), ctx.email_account)

      assert_nothing_created(ctx)
    end

    test "does not skip Auto-Submitted: no", ctx do
      raw =
        raw_email(
          [
            {"Message-ID", "<not-auto-001@customer.test>"},
            {"From", "jane@customer.test"},
            {"To", "support@company.test"},
            {"Subject", "Manual mail"},
            {"Auto-Submitted", "no"}
          ],
          "A human wrote this."
        )

      assert {:ok, %Message{}} = Ingestion.process_raw_email(raw, ctx.email_account)
    end

    test "skips X-Autoreply and X-Autorespond mail", ctx do
      for header <- ["X-Autoreply", "X-Autorespond"] do
        raw =
          raw_email(
            [
              {"Message-ID", "<autoresponder-#{header}@customer.test>"},
              {"From", "jane@customer.test"},
              {"To", "support@company.test"},
              {"Subject", "Out of office"},
              {header, "yes"}
            ],
            "I am away."
          )

        assert {:ok, :skipped} = Ingestion.process_raw_email(raw, ctx.email_account)
      end

      assert_nothing_created(ctx)
    end

    test "skips mail from the account's own from_address (self-loop/bounce)", ctx do
      raw =
        raw_email(
          [
            {"Message-ID", "<self-001@company.test>"},
            {"From", "Support <SUPPORT@company.test>"},
            {"To", "jane@customer.test"},
            {"Subject", "Re: Need help with my account"}
          ],
          "Our own outbound mail showing up in the inbox."
        )

      assert {:ok, :skipped} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert_nothing_created(ctx)
    end

    test "skips mail from the account's IMAP username", ctx do
      raw =
        raw_email(
          [
            {"Message-ID", "<self-002@company.test>"},
            {"From", "imap-login@company.test"},
            {"To", "jane@customer.test"},
            {"Subject", "Also our own address"}
          ],
          "Self-addressed via the login identity."
        )

      assert {:ok, :skipped} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert_nothing_created(ctx)
    end
  end

  describe "process_raw_email/2 — failure modes" do
    test "returns {:error, :parse_failure} for poison messages", ctx do
      assert {:error, :parse_failure} =
               Ingestion.process_raw_email(fixture("poison.eml"), ctx.email_account)

      assert_nothing_created(ctx)
    end

    test "returns {:error, :parse_failure} when there is no usable From address", ctx do
      raw =
        raw_email(
          [
            {"Message-ID", "<no-from-001@customer.test>"},
            {"To", "support@company.test"},
            {"Subject", "Anonymous"}
          ],
          "Who sent this?"
        )

      assert {:error, :parse_failure} = Ingestion.process_raw_email(raw, ctx.email_account)
      assert_nothing_created(ctx)
    end
  end

  describe "round trip with the outbound SMTP worker (stage 2)" do
    test "inbound email_message_id becomes the In-Reply-To of the next outbound reply — " <>
           "and the customer's follow-up threads back into the same conversation",
         ctx do
      # 1. Inbound customer email creates the conversation
      assert {:ok, %Message{} = inbound} =
               Ingestion.process_raw_email(fixture("simple.eml"), ctx.email_account)

      conversation = Conversations.get_conversation!(inbound.conversation_id)

      # 2. An agent replies from the dashboard; the stage-2 worker sends it
      #    over SMTP, threading onto the inbound message
      reply =
        insert(:message,
          account: ctx.account,
          conversation: conversation,
          user: ctx.agent,
          customer: nil,
          body: "Happy to help — try resetting your password."
        )

      test_pid = self()

      with_mock ChatApi.Mailers,
        deliver: fn email, _config ->
          send(test_pid, {:delivered, email})
          {:ok, %{}}
        end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => reply.id})
        assert_receive {:delivered, email}

        assert email.headers["In-Reply-To"] == "<simple-001@customer.test>"
        assert email.headers["References"] == "<simple-001@customer.test>"
        assert email.to == [{"", "jane@customer.test"}]
        assert email.subject == "Re: Need help with my account"
      end

      outbound_message_id = Messages.get_message!(reply.id).metadata["email_message_id"]
      assert outbound_message_id =~ ~r/^<[0-9a-f\-]{36}@company\.test>$/

      # 3. The customer replies to the outbound email; References now carry
      #    the outbound Message-ID and the reply threads into the same
      #    conversation
      followup =
        raw_email(
          [
            {"Message-ID", "<followup-001@customer.test>"},
            {"From", "Jane Customer <jane@customer.test>"},
            {"To", "support@company.test"},
            {"Subject", "Re: Need help with my account"},
            {"In-Reply-To", outbound_message_id},
            {"References", "<simple-001@customer.test> #{outbound_message_id}"}
          ],
          "That worked, thank you!"
        )

      assert {:ok, %Message{} = followup_message} =
               Ingestion.process_raw_email(followup, ctx.email_account)

      assert followup_message.conversation_id == conversation.id
      assert count_conversations(ctx.account.id) == 1
    end
  end

  ## Helpers

  defp insert_email_conversation(ctx, attrs \\ []) do
    insert(
      :conversation,
      Keyword.merge(
        [
          account: ctx.account,
          inbox: ctx.inbox,
          source: "email",
          status: "open",
          subject: "Need help with my account"
        ],
        attrs
      )
    )
  end

  # A previously sent outbound message carrying the email_message_id that
  # inbound replies reference.
  defp insert_thread_anchor(ctx, conversation) do
    insert(:message,
      account: ctx.account,
      conversation: conversation,
      user: ctx.agent,
      customer: nil,
      source: "email",
      metadata: %{
        "email_message_id" => "<outbound-001@company.test>",
        "email_subject" => "Need help with my account",
        "email_from" => "jane@customer.test",
        "email_account_id" => ctx.email_account.id
      }
    )
  end

  defp assert_nothing_created(ctx) do
    assert count_messages(ctx.account.id) == 0
    assert count_conversations(ctx.account.id) == 0
    assert Customers.find_by_email("jane@customer.test", ctx.account.id) == nil
  end
end
