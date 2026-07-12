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
end
