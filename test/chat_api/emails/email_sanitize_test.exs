defmodule ChatApi.Emails.EmailSanitizeTest do
  use ExUnit.Case, async: true

  alias ChatApi.Emails.Email

  test "conversation_reply strips XSS from user-supplied message bodies" do
    message = %{
      body:
        "Hello <script>alert(1)</script> <img src=x onerror=alert(1)> [x](javascript:alert(1))",
      customer_id: "c1"
    }

    customer = %{name: "Ada", current_url: "https://example.com"}

    email =
      Email.conversation_reply(
        to: "agent@example.com",
        from: "Support",
        reply_to: "reply@example.com",
        company: "Acme",
        messages: [message],
        customer: customer
      )

    html = email.html_body
    # No active script/img tags or javascript: URLs survive (dangerous HTML is
    # escaped to inert text and unsafe link hrefs are stripped).
    refute html =~ "<script"
    refute html =~ "<img"
    refute html =~ "javascript:"
    # Benign content survives sanitization.
    assert html =~ "Hello"
  end
end
