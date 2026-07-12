defmodule ChatApi.EmailChannels.MimeTest do
  use ExUnit.Case, async: true

  alias ChatApi.EmailAccounts.EmailAccount
  alias ChatApi.EmailChannels.Mime

  @fixtures Path.expand("../../fixtures/email", __DIR__)

  @email_account %EmailAccount{id: "b7a1f6ea-13a9-460a-9a54-52b0eff4d363"}

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  describe "parse/1" do
    test "parses a simple plain-text email" do
      assert {:ok, email} = Mime.parse(fixture("simple.eml"))

      assert email.message_id == "<simple-001@customer.test>"
      assert email.subject == "Need help with my account"
      assert email.from == {"Jane Customer", "jane@customer.test"}
      assert email.to == [{"Support", "support@company.test"}]
      assert email.in_reply_to == nil
      assert email.references == []
      assert %DateTime{} = email.date

      assert email.text =~ "Hello, I cannot log in to my account"
      assert email.formatted_text =~ "Hello, I cannot log in to my account"
      assert email.attachments == []
    end

    test "parses a multipart email with alternative bodies and a decoded attachment" do
      assert {:ok, email} = Mime.parse(fixture("multipart_attachment.eml"))

      assert email.message_id == "<multipart-001@customer.test>"
      assert email.text == "Please find the invoice attached."
      assert email.formatted_text == "Please find the invoice attached."
      assert email.html == "<p>Please find the invoice <b>attached</b>.</p>"

      assert [attachment] = email.attachments
      assert attachment.filename == "invoice.pdf"
      assert attachment.content_type == "application/pdf"
      # Content-Transfer-Encoding: base64 is decoded by the parser
      assert attachment.body == "%PDF-1.4 fake invoice bytes for testing"
    end

    test "parses threading headers from a reply (including folded References)" do
      assert {:ok, email} = Mime.parse(fixture("reply_with_references.eml"))

      assert email.message_id == "<reply-001@customer.test>"
      assert email.in_reply_to == "<outbound-001@company.test>"
      assert email.references == ["<simple-001@customer.test>", "<outbound-001@company.test>"]
      assert email.subject == "Re: Need help with my account"
    end

    test "keeps loop-detection headers accessible" do
      assert {:ok, auto} = Mime.parse(fixture("auto_submitted.eml"))
      assert auto.headers["auto-submitted"] == "auto-replied"

      assert {:ok, bulk} = Mime.parse(fixture("bulk_precedence.eml"))
      assert bulk.headers["precedence"] == "bulk"
    end

    test "returns an error tuple (instead of raising) for a poison message" do
      assert {:error, _reason} = Mime.parse(fixture("poison.eml"))
    end

    test "returns an error tuple for empty or non-binary input" do
      assert {:error, _reason} = Mime.parse("")
      assert {:error, _reason} = Mime.parse(nil)
    end

    test "parses LF-only messages by normalizing line endings" do
      raw =
        Enum.join(
          [
            "Message-ID: <lf-only@customer.test>",
            "From: jane@customer.test",
            "To: support@company.test",
            "Subject: LF only",
            "",
            "unix line endings"
          ],
          "\n"
        )

      assert {:ok, email} = Mime.parse(raw)
      assert email.message_id == "<lf-only@customer.test>"
      assert email.text == "unix line endings"
    end

    test "classifies a single-part HTML email as html (not text)" do
      raw =
        Enum.join(
          [
            "Message-ID: <html-only@customer.test>",
            "From: jane@customer.test",
            "To: support@company.test",
            "Subject: HTML only",
            "Content-Type: text/html; charset=utf-8",
            "",
            "<p>rich content</p>"
          ],
          "\r\n"
        )

      assert {:ok, email} = Mime.parse(raw)
      assert email.html == "<p>rich content</p>"
      assert email.text == nil
      assert email.formatted_text == nil
    end
  end

  describe "format_message_metadata/2" do
    test "formats email_* metadata compatible with the outbound reply worker" do
      {:ok, email} = Mime.parse(fixture("reply_with_references.eml"))

      assert %{
               "email_message_id" => "<reply-001@customer.test>",
               "email_in_reply_to" => "<outbound-001@company.test>",
               "email_references" => "<simple-001@customer.test> <outbound-001@company.test>",
               "email_subject" => "Re: Need help with my account",
               "email_from" => "jane@customer.test",
               "email_to" => ["support@company.test"],
               "email_account_id" => "b7a1f6ea-13a9-460a-9a54-52b0eff4d363"
             } = Mime.format_message_metadata(email, @email_account)
    end

    test "stores nil references when the email has none" do
      {:ok, email} = Mime.parse(fixture("simple.eml"))
      metadata = Mime.format_message_metadata(email, @email_account)

      assert metadata["email_references"] == nil
      assert metadata["email_message_id"] == "<simple-001@customer.test>"
      refute Map.has_key?(metadata, "email_html")
    end

    test "keeps the raw html around when there is no plain-text body" do
      raw =
        Enum.join(
          [
            "Message-ID: <html-only@customer.test>",
            "From: jane@customer.test",
            "To: support@company.test",
            "Subject: HTML only",
            "Content-Type: text/html; charset=utf-8",
            "",
            "<p>rich content</p>"
          ],
          "\r\n"
        )

      {:ok, email} = Mime.parse(raw)
      metadata = Mime.format_message_metadata(email, @email_account)

      assert metadata["email_html"] == "<p>rich content</p>"
    end
  end

  describe "extract_email_address/1" do
    test "handles parsed tuples, bare strings, name-addr strings and lists" do
      assert Mime.extract_email_address({"Jane", "jane@customer.test"}) == "jane@customer.test"
      assert Mime.extract_email_address("jane@customer.test") == "jane@customer.test"
      assert Mime.extract_email_address("Jane <jane@customer.test>") == "jane@customer.test"

      assert Mime.extract_email_address([{"Jane", "jane@customer.test"}, "x@y.test"]) ==
               "jane@customer.test"

      assert Mime.extract_email_address(nil) == nil
      assert Mime.extract_email_address("") == nil
    end
  end

  describe "normalize_message_id/1" do
    test "extracts the canonical <...> form" do
      assert Mime.normalize_message_id("<abc@def>") == "<abc@def>"
      assert Mime.normalize_message_id("  <abc@def>  ") == "<abc@def>"
      assert Mime.normalize_message_id("abc@def") == "abc@def"
      assert Mime.normalize_message_id(nil) == nil
      assert Mime.normalize_message_id("   ") == nil
    end
  end

  describe "reference_ids/1" do
    test "extracts all message ids" do
      assert Mime.reference_ids("<a@b> <c@d>") == ["<a@b>", "<c@d>"]
      assert Mime.reference_ids("<a@b>\r\n <c@d>") == ["<a@b>", "<c@d>"]
      assert Mime.reference_ids("bare-id@host") == ["bare-id@host"]
      assert Mime.reference_ids(nil) == []
      assert Mime.reference_ids("  ") == []
    end
  end
end
