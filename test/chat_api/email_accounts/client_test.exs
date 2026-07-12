defmodule ChatApi.EmailAccounts.ClientTest do
  use ExUnit.Case, async: true

  alias ChatApi.EmailAccounts.Client
  alias ChatApi.EmailAccounts.EmailAccount

  @email_account %EmailAccount{
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

  describe "imap_opts/1" do
    test "builds ssl-on-connect options for tls \"ssl\"" do
      opts = Client.imap_opts(@email_account)

      assert opts[:ssl] == true
      assert opts[:port] == 993

      ssl_opts = opts[:ssl_opts]
      assert ssl_opts[:verify] == :verify_peer
      assert is_list(ssl_opts[:cacerts]) and ssl_opts[:cacerts] != []
      assert ssl_opts[:server_name_indication] == ~c"imap.company.test"
      assert ssl_opts[:depth] == 3
    end

    test "builds plain-connect options for tls \"starttls\" with secure upgrade opts" do
      opts =
        Client.imap_opts(%EmailAccount{@email_account | imap_tls: "starttls", imap_port: 143})

      assert opts[:ssl] == false
      assert opts[:port] == 143
      # The ssl_opts are applied by mailroom when the connection is upgraded
      # via STARTTLS after the server advertises the capability.
      assert opts[:ssl_opts][:verify] == :verify_peer
      assert opts[:ssl_opts][:server_name_indication] == ~c"imap.company.test"
    end

    test "builds plain options for tls \"none\"" do
      opts = Client.imap_opts(%EmailAccount{@email_account | imap_tls: "none", imap_port: 143})

      assert opts[:ssl] == false
      assert opts[:port] == 143
      # No TLS requested: an opportunistic upgrade should not fail on cert checks.
      assert opts[:ssl_opts] == [verify: :verify_none]
    end

    test "disables certificate verification when allow_insecure_tls is set" do
      opts =
        Client.imap_opts(%EmailAccount{
          @email_account
          | settings: %{"allow_insecure_tls" => true}
        })

      assert opts[:ssl] == true
      assert opts[:ssl_opts] == [verify: :verify_none]
    end

    test "accepts a plain attrs map with string keys and applies defaults" do
      opts =
        Client.imap_opts(%{
          "imap_host" => "imap.company.test",
          "imap_username" => "imap-user",
          "imap_password" => "imap-pass"
        })

      assert opts[:ssl] == true
      assert opts[:port] == 993
      assert opts[:ssl_opts][:verify] == :verify_peer
    end
  end

  describe "smtp_opts/1" do
    test "builds STARTTLS options for tls \"starttls\"" do
      opts = Client.smtp_opts(@email_account)

      assert opts[:relay] == "smtp.company.test"
      assert opts[:port] == 587
      assert opts[:ssl] == false
      assert opts[:tls] == :always
      assert opts[:no_mx_lookups] == true
      assert opts[:auth] == :always

      tls_options = opts[:tls_options]
      assert tls_options[:verify] == :verify_peer
      assert tls_options[:server_name_indication] == ~c"smtp.company.test"
      assert tls_options[:depth] == 3
    end

    test "builds implicit-ssl options for tls \"ssl\"" do
      opts = Client.smtp_opts(%EmailAccount{@email_account | smtp_tls: "ssl", smtp_port: 465})

      assert opts[:ssl] == true
      assert opts[:port] == 465
      assert opts[:tls] == :never
      # gen_smtp only applies :sockopts (not :tls_options) on an implicit ssl connect.
      assert opts[:sockopts][:verify] == :verify_peer
      assert opts[:sockopts][:server_name_indication] == ~c"smtp.company.test"
    end

    test "builds plain options for tls \"none\"" do
      opts = Client.smtp_opts(%EmailAccount{@email_account | smtp_tls: "none", smtp_port: 25})

      assert opts[:ssl] == false
      assert opts[:port] == 25
      assert opts[:tls] == :never
      refute Keyword.has_key?(opts, :tls_options)
      refute Keyword.has_key?(opts, :sockopts)
    end

    test "falls back to the IMAP credentials when SMTP credentials are blank" do
      opts = Client.smtp_opts(@email_account)

      assert opts[:username] == "imap-user"
      assert opts[:password] == "imap-pass"
    end

    test "uses the SMTP credentials when present" do
      opts =
        Client.smtp_opts(%EmailAccount{
          @email_account
          | smtp_username: "smtp-user",
            smtp_password: "smtp-pass"
        })

      assert opts[:username] == "smtp-user"
      assert opts[:password] == "smtp-pass"
    end

    test "disables certificate verification when allow_insecure_tls is set" do
      opts =
        Client.smtp_opts(%EmailAccount{
          @email_account
          | settings: %{"allow_insecure_tls" => true}
        })

      assert opts[:tls_options] == [verify: :verify_none]
    end

    test "accepts a plain attrs map with string keys and applies defaults" do
      opts =
        Client.smtp_opts(%{
          "imap_username" => "imap-user",
          "imap_password" => "imap-pass",
          "smtp_host" => "smtp.company.test"
        })

      assert opts[:relay] == "smtp.company.test"
      assert opts[:port] == 587
      assert opts[:tls] == :always
      assert opts[:username] == "imap-user"
      assert opts[:password] == "imap-pass"
    end
  end

  describe "fetch_unseen/2 and mark_seen/2 (against a real IMAP socket)" do
    @fixtures Path.expand("../../fixtures/email", __DIR__)

    defp fixture(name), do: File.read!(Path.join(@fixtures, name))

    defp sink_account(port) do
      %EmailAccount{
        from_address: "support@company.test",
        imap_host: "127.0.0.1",
        imap_port: port,
        imap_tls: "none",
        imap_username: "imap-user",
        imap_password: "imap-pass",
        imap_folder: "INBOX",
        settings: %{}
      }
    end

    test "fetches unseen messages byte-for-byte (uid + raw) via UID commands" do
      simple = fixture("simple.eml")
      reply = fixture("reply_with_references.eml")

      {:ok, port} = ChatApi.ImapSink.start(messages: %{5 => simple, 7 => reply})

      assert {:ok, [%{uid: 5, raw: ^simple}, %{uid: 7, raw: ^reply}]} =
               Client.fetch_unseen(sink_account(port))

      assert_received {:imap_sink, "SELECT INBOX"}
      assert_received {:imap_sink, "UID SEARCH UNSEEN"}
      assert_received {:imap_sink, "UID FETCH 5 (BODY.PEEK[])"}
      assert_received {:imap_sink, "UID FETCH 7 (BODY.PEEK[])"}
    end

    test "fetches at most `limit` messages (oldest uid first)" do
      simple = fixture("simple.eml")
      reply = fixture("reply_with_references.eml")

      {:ok, port} = ChatApi.ImapSink.start(messages: %{7 => reply, 5 => simple})

      assert {:ok, [%{uid: 5, raw: ^simple}]} = Client.fetch_unseen(sink_account(port), 1)

      assert_received {:imap_sink, "UID FETCH 5 (BODY.PEEK[])"}
      refute_received {:imap_sink, "UID FETCH 7" <> _}
    end

    test "returns an empty list for a mailbox without unseen messages" do
      {:ok, port} = ChatApi.ImapSink.start(messages: %{})

      assert {:ok, []} = Client.fetch_unseen(sink_account(port))

      assert_received {:imap_sink, "UID SEARCH UNSEEN"}
      refute_received {:imap_sink, "UID FETCH" <> _}
    end

    test "marks uids seen via UID STORE, grouping contiguous uids into ranges" do
      {:ok, port} = ChatApi.ImapSink.start(messages: %{})

      assert :ok = Client.mark_seen(sink_account(port), [6, 5, 9])

      assert_received {:imap_sink, "UID STORE 5:6 +FLAGS.SILENT (\\Seen)"}
      assert_received {:imap_sink, "UID STORE 9 +FLAGS.SILENT (\\Seen)"}
    end

    test "mark_seen with no uids is a no-op (no connection is made)" do
      assert :ok = Client.mark_seen(sink_account(1), [])
    end

    test "surfaces authentication failures as human-readable errors" do
      {:ok, port} = ChatApi.ImapSink.start(deny: ["LOGIN"])

      assert {:error, "Authentication failed: LOGIN denied by test script"} =
               Client.fetch_unseen(sink_account(port))
    end

    test "surfaces folder-selection failures as human-readable errors" do
      {:ok, port} = ChatApi.ImapSink.start(deny: ["SELECT"])

      assert {:error, "Could not open folder INBOX: SELECT denied by test script"} =
               Client.mark_seen(sink_account(port), [1])
    end

    test "surfaces connection failures as human-readable errors" do
      # Grab an ephemeral port and close it again so nothing is listening.
      {:ok, listen} = :gen_tcp.listen(0, [])
      {:ok, port} = :inet.port(listen)
      :ok = :gen_tcp.close(listen)

      assert {:error, "Unable to connect to server — check host and port"} =
               Client.fetch_unseen(sink_account(port))
    end
  end
end
