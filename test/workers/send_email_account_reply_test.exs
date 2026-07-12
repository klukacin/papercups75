defmodule ChatApi.SendEmailAccountReplyTest do
  use ChatApi.DataCase
  use Oban.Testing, repo: ChatApi.Repo

  import ChatApi.Factory
  import Mock

  alias ChatApi.EmailAccounts.EmailAccount
  alias ChatApi.Messages
  alias ChatApi.Workers.SendEmailAccountReply

  @previous_metadata %{
    "email_message_id" => "<inbound@customer.test>",
    "email_references" => "<older@customer.test>",
    "email_subject" => "Need help with my account",
    "email_from" => "customer@customer.test"
  }

  setup do
    account = insert(:account, company_name: "Test Co")
    inbox = insert(:inbox, account: account)
    user = insert(:user, account: account)
    customer = insert(:customer, account: account, email: "customer@customer.test")

    conversation =
      insert(:conversation,
        account: account,
        inbox: inbox,
        customer: customer,
        source: "email"
      )

    {:ok,
     account: account, inbox: inbox, user: user, customer: customer, conversation: conversation}
  end

  defp insert_email_account(context, attrs \\ []) do
    insert(
      :email_account,
      Keyword.merge(
        [
          account: context.account,
          inbox: context.inbox,
          from_address: "support@company.test",
          smtp_host: "smtp.company.test",
          smtp_port: 587,
          smtp_tls: "starttls"
        ],
        attrs
      )
    )
  end

  defp insert_inbound_email(context, metadata \\ @previous_metadata, attrs \\ []) do
    insert(
      :message,
      Keyword.merge(
        [
          account: context.account,
          conversation: context.conversation,
          customer: context.customer,
          user: nil,
          inserted_at: ~N[2020-01-01 00:00:00],
          metadata: metadata
        ],
        attrs
      )
    )
  end

  defp insert_reply(context, attrs \\ []) do
    insert(
      :message,
      Keyword.merge(
        [
          account: context.account,
          conversation: context.conversation,
          user: context.user,
          customer: nil,
          body: "some message body"
        ],
        attrs
      )
    )
  end

  describe "perform/1" do
    test "sends the reply through the inbox SMTP account and persists email_* metadata", ctx do
      email_account = insert_email_account(ctx)
      insert_inbound_email(ctx)
      message = insert_reply(ctx)
      test_pid = self()

      with_mock ChatApi.Mailers,
        deliver: fn email, config ->
          send(test_pid, {:delivered, email, config})
          {:ok, %{}}
        end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})

        assert_receive {:delivered, %Swoosh.Email{} = email, config}

        assert email.to == [{"", "customer@customer.test"}]
        assert email.from == {"Test Co Team", "support@company.test"}
        assert email.subject == "Re: Need help with my account"
        assert email.text_body == "some message body"
        assert email.headers["In-Reply-To"] == "<inbound@customer.test>"
        assert email.headers["References"] == "<older@customer.test> <inbound@customer.test>"
        assert email.headers["Message-ID"] =~ ~r/^<[0-9a-f\-]{36}@company\.test>$/

        assert config[:adapter] == Swoosh.Adapters.SMTP
        assert config[:relay] == "smtp.company.test"

        updated = Messages.get_message!(message.id)
        sent_message_id = email.headers["Message-ID"]

        assert %{
                 "email_message_id" => ^sent_message_id,
                 "email_in_reply_to" => "<inbound@customer.test>",
                 "email_references" => "<older@customer.test> <inbound@customer.test>",
                 "email_subject" => "Re: Need help with my account",
                 "email_from" => "customer@customer.test",
                 "email_account_id" => email_account_id
               } = updated.metadata

        assert email_account_id == email_account.id
      end
    end

    test "threads off the most recent message with email metadata", ctx do
      insert_email_account(ctx)
      insert_inbound_email(ctx)

      insert_inbound_email(
        ctx,
        %{
          "email_message_id" => "<latest@customer.test>",
          "email_references" => "<older@customer.test> <inbound@customer.test>"
        },
        inserted_at: ~N[2020-01-02 00:00:00]
      )

      message = insert_reply(ctx)
      test_pid = self()

      with_mock ChatApi.Mailers,
        deliver: fn email, _config ->
          send(test_pid, {:delivered, email})
          {:ok, %{}}
        end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})

        assert_receive {:delivered, email}
        assert email.headers["In-Reply-To"] == "<latest@customer.test>"

        assert email.headers["References"] ==
                 "<older@customer.test> <inbound@customer.test> <latest@customer.test>"
      end
    end

    test "sends to the address the previous email came from", ctx do
      insert_email_account(ctx)

      insert_inbound_email(ctx, %{
        "email_message_id" => "<inbound@customer.test>",
        "email_from" => "someone-else@external.test"
      })

      message = insert_reply(ctx)
      test_pid = self()

      with_mock ChatApi.Mailers,
        deliver: fn email, _config ->
          send(test_pid, {:delivered, email})
          {:ok, %{}}
        end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})

        assert_receive {:delivered, email}
        assert email.to == [{"", "someone-else@external.test"}]
      end
    end

    test "falls back to the conversation customer's email when metadata has no sender", ctx do
      insert_email_account(ctx)
      insert_inbound_email(ctx, %{"email_message_id" => "<inbound@customer.test>"})
      message = insert_reply(ctx)
      test_pid = self()

      with_mock ChatApi.Mailers,
        deliver: fn email, _config ->
          send(test_pid, {:delivered, email})
          {:ok, %{}}
        end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})

        assert_receive {:delivered, email}
        assert email.to == [{"", "customer@customer.test"}]
        # No previous references: the References header is just the replied-to id
        assert email.headers["References"] == "<inbound@customer.test>"
      end
    end

    test "falls back to the conversation subject when metadata has no subject", ctx do
      conversation =
        insert(:conversation,
          account: ctx.account,
          inbox: ctx.inbox,
          customer: ctx.customer,
          source: "email",
          subject: "Original conversation subject"
        )

      ctx = Map.put(ctx, :conversation, conversation)

      insert_email_account(ctx)
      insert_inbound_email(ctx, %{"email_message_id" => "<inbound@customer.test>"})
      message = insert_reply(ctx)
      test_pid = self()

      with_mock ChatApi.Mailers,
        deliver: fn email, _config ->
          send(test_pid, {:delivered, email})
          {:ok, %{}}
        end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})

        assert_receive {:delivered, email}
        assert email.subject == "Re: Original conversation subject"
      end
    end

    test "no-ops when the inbox has no email account", ctx do
      insert_inbound_email(ctx)
      message = insert_reply(ctx)

      with_mock ChatApi.Mailers, deliver: fn _email, _config -> {:ok, %{}} end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})
        assert_not_called(ChatApi.Mailers.deliver(:_, :_))
        assert Messages.get_message!(message.id).metadata == nil
      end
    end

    test "no-ops when the email account is not active", ctx do
      insert_email_account(ctx, status: "disabled")
      insert_inbound_email(ctx)
      message = insert_reply(ctx)

      with_mock ChatApi.Mailers, deliver: fn _email, _config -> {:ok, %{}} end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})
        assert_not_called(ChatApi.Mailers.deliver(:_, :_))
      end
    end

    test "no-ops when the conversation has no prior email_* metadata", ctx do
      insert_email_account(ctx)
      insert_inbound_email(ctx, %{"foo" => "bar"})
      message = insert_reply(ctx)

      with_mock ChatApi.Mailers, deliver: fn _email, _config -> {:ok, %{}} end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})
        assert_not_called(ChatApi.Mailers.deliver(:_, :_))
        assert Messages.get_message!(message.id).metadata == nil
      end
    end

    test "never sends for conversations that only carry SES metadata", ctx do
      insert_email_account(ctx)

      insert_inbound_email(ctx, %{
        "ses_message_id" => "<previous@email.amazonses.com>",
        "ses_references" => "<reference@email.amazonses.com>",
        "ses_subject" => "Test subject line",
        "ses_from" => "test@papercups.io"
      })

      message = insert_reply(ctx)

      with_mock ChatApi.Mailers, deliver: fn _email, _config -> {:ok, %{}} end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})
        assert_not_called(ChatApi.Mailers.deliver(:_, :_))
      end
    end

    test "no-ops for customer (userless) messages", ctx do
      insert_email_account(ctx)
      insert_inbound_email(ctx)

      message =
        insert(:message,
          account: ctx.account,
          conversation: ctx.conversation,
          customer: ctx.customer,
          user: nil
        )

      with_mock ChatApi.Mailers, deliver: fn _email, _config -> {:ok, %{}} end do
        assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})
        assert_not_called(ChatApi.Mailers.deliver(:_, :_))
      end
    end

    test "returns an error (so Oban retries) when delivery fails", ctx do
      insert_email_account(ctx)
      insert_inbound_email(ctx)
      message = insert_reply(ctx)

      with_mock ChatApi.Mailers,
        deliver: fn _email, _config ->
          {:error, {:network_failure, ~c"smtp.company.test", {:error, :econnrefused}}}
        end do
        assert {:error, _reason} =
                 perform_job(SendEmailAccountReply, %{"message_id" => message.id})

        assert Messages.get_message!(message.id).metadata == nil
      end
    end
  end

  describe "sending through a real SMTP server" do
    test "delivers the composed email over the wire with threading headers", ctx do
      server_name = :"smtp_sink_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        :gen_smtp_server.start(server_name, ChatApi.SmtpSink,
          port: 0,
          address: {127, 0, 0, 1},
          domain: ~c"sink.test",
          sessionoptions: [callbackoptions: [forward_to: self()]]
        )

      on_exit(fn -> :gen_smtp_server.stop(server_name) end)

      port = :ranch.get_port(server_name)

      insert_email_account(ctx,
        from_address: "support@company.test",
        smtp_host: "127.0.0.1",
        smtp_port: port,
        smtp_tls: "none",
        smtp_username: "smtp-user",
        smtp_password: "smtp-pass"
      )

      insert_inbound_email(ctx)
      message = insert_reply(ctx, body: "Happy to help! Let me look into it.")

      assert :ok = perform_job(SendEmailAccountReply, %{"message_id" => message.id})

      assert_receive {:smtp_sink, %{from: from, to: to, data: data}}, 10_000

      assert from == "support@company.test"
      assert to == ["customer@customer.test"]

      updated = Messages.get_message!(message.id)
      sent_message_id = updated.metadata["email_message_id"]
      assert sent_message_id =~ ~r/^<[0-9a-f\-]{36}@company\.test>$/

      assert data =~ "From: Test Co Team <support@company.test>"
      assert data =~ "To: customer@customer.test"
      assert data =~ "Subject: Re: Need help with my account"
      assert data =~ "In-Reply-To: <inbound@customer.test>"
      assert data =~ "References: <older@customer.test> <inbound@customer.test>"
      assert data =~ "Message-ID: #{sent_message_id}"
      assert data =~ "Happy to help! Let me look into it."
    end
  end

  describe "smtp_config_for/1" do
    @email_account %EmailAccount{
      id: "b7a1f6ea-13a9-460a-9a54-52b0eff4d363",
      from_address: "support@company.test",
      imap_host: "imap.company.test",
      imap_port: 993,
      imap_tls: "ssl",
      imap_username: "imap-user",
      imap_password: "imap-pass",
      imap_folder: "INBOX",
      smtp_host: "smtp.company.test",
      smtp_port: 587,
      smtp_tls: "starttls",
      smtp_username: nil,
      smtp_password: nil,
      settings: %{}
    }

    test "builds STARTTLS config for tls \"starttls\", falling back to IMAP credentials" do
      config = SendEmailAccountReply.smtp_config_for(@email_account)

      assert config[:adapter] == Swoosh.Adapters.SMTP
      assert config[:relay] == "smtp.company.test"
      assert config[:port] == 587
      assert config[:ssl] == false
      assert config[:tls] == :always
      assert config[:auth] == :always
      assert config[:username] == "imap-user"
      assert config[:password] == "imap-pass"
      assert config[:no_mx_lookups] == true
      assert config[:retries] == 1

      tls_options = config[:tls_options]
      assert tls_options[:verify] == :verify_peer
      assert is_list(tls_options[:cacerts]) and tls_options[:cacerts] != []
      assert tls_options[:server_name_indication] == ~c"smtp.company.test"
      assert tls_options[:depth] == 3
    end

    test "prefers explicit SMTP credentials over the IMAP fallback" do
      config =
        SendEmailAccountReply.smtp_config_for(%EmailAccount{
          @email_account
          | smtp_username: "smtp-user",
            smtp_password: "smtp-pass"
        })

      assert config[:username] == "smtp-user"
      assert config[:password] == "smtp-pass"
      assert config[:auth] == :always
    end

    test "builds implicit-ssl config for tls \"ssl\"" do
      config =
        SendEmailAccountReply.smtp_config_for(%EmailAccount{
          @email_account
          | smtp_tls: "ssl",
            smtp_port: 465
        })

      assert config[:ssl] == true
      assert config[:port] == 465
      assert config[:tls] == :never
      # gen_smtp only applies :sockopts (not :tls_options) on an implicit ssl connect.
      assert config[:sockopts][:verify] == :verify_peer
      assert config[:sockopts][:server_name_indication] == ~c"smtp.company.test"
      refute Keyword.has_key?(config, :tls_options)
    end

    test "builds plain config for tls \"none\"" do
      config =
        SendEmailAccountReply.smtp_config_for(%EmailAccount{
          @email_account
          | smtp_tls: "none",
            smtp_port: 25
        })

      assert config[:ssl] == false
      assert config[:port] == 25
      assert config[:tls] == :never
      refute Keyword.has_key?(config, :tls_options)
      refute Keyword.has_key?(config, :sockopts)
    end

    test "disables certificate verification when allow_insecure_tls is set" do
      config =
        SendEmailAccountReply.smtp_config_for(%EmailAccount{
          @email_account
          | settings: %{"allow_insecure_tls" => true}
        })

      assert config[:tls_options] == [verify: :verify_none]
    end

    test "relaxes auth to :if_available when no credentials are available at all" do
      config =
        SendEmailAccountReply.smtp_config_for(%EmailAccount{
          @email_account
          | imap_username: nil,
            imap_password: nil
        })

      assert config[:auth] == :if_available
      # Swoosh's SMTP adapter requires string credentials when the keys are
      # present, so blank credentials must be omitted entirely.
      refute Keyword.has_key?(config, :username)
      refute Keyword.has_key?(config, :password)
    end
  end

  describe "generate_message_id/1" do
    test "generates a unique message id scoped to the sender's domain" do
      message_id = SendEmailAccountReply.generate_message_id("support@company.test")

      assert message_id =~ ~r/^<[0-9a-f\-]{36}@company\.test>$/
      refute message_id == SendEmailAccountReply.generate_message_id("support@company.test")
    end

    test "falls back to localhost for addresses without a domain" do
      assert SendEmailAccountReply.generate_message_id("invalid") =~ ~r/@localhost>$/
      assert SendEmailAccountReply.generate_message_id(nil) =~ ~r/@localhost>$/
    end
  end

  describe "domain_of/1" do
    test "extracts the domain part of an email address" do
      assert SendEmailAccountReply.domain_of("support@company.test") == "company.test"
    end

    test "falls back to localhost when there is no domain" do
      assert SendEmailAccountReply.domain_of("invalid") == "localhost"
      assert SendEmailAccountReply.domain_of("trailing@") == "localhost"
      assert SendEmailAccountReply.domain_of(nil) == "localhost"
    end
  end

  describe "build_references/2" do
    test "starts a references chain from the replied-to message id" do
      assert SendEmailAccountReply.build_references(nil, "<a@b.test>") == "<a@b.test>"
      assert SendEmailAccountReply.build_references("", "<a@b.test>") == "<a@b.test>"
    end

    test "appends the replied-to message id to the existing references" do
      assert SendEmailAccountReply.build_references("<x@y.test> <z@w.test>", "<a@b.test>") ==
               "<x@y.test> <z@w.test> <a@b.test>"
    end
  end

  describe "build_subject/2" do
    test "prefixes the previous email subject with Re:" do
      assert SendEmailAccountReply.build_subject("Need help", nil) == "Re: Need help"
    end

    test "does not stack Re: prefixes" do
      assert SendEmailAccountReply.build_subject("Re: Need help", nil) == "Re: Need help"
      assert SendEmailAccountReply.build_subject("RE: Need help", nil) == "RE: Need help"
    end

    test "falls back to the conversation subject" do
      assert SendEmailAccountReply.build_subject(nil, "Original subject") ==
               "Re: Original subject"

      assert SendEmailAccountReply.build_subject("", "Original subject") ==
               "Re: Original subject"
    end

    test "returns an empty subject when there is nothing to reply to" do
      assert SendEmailAccountReply.build_subject(nil, nil) == ""
    end
  end
end
