defmodule ChatApiWeb.MessageJSON do
  import ChatApiWeb.JSONHelpers
  alias ChatApiWeb.{CustomerJSON, FileJSON, UserJSON}

  def index(%{messages: messages}) do
    %{data: Enum.map(messages, &message/1)}
  end

  def show(%{message: message}) do
    %{data: maybe(message, &expanded/1)}
  end

  def message(message) do
    %{
      id: message.id,
      object: "message",
      body: message.body,
      type: message.type,
      content_type: message.content_type,
      private: message.private,
      source: message.source,
      created_at: message.inserted_at,
      sent_at: message.sent_at,
      seen_at: message.seen_at,
      customer_id: message.customer_id,
      conversation_id: message.conversation_id,
      account_id: message.account_id,
      user_id: message.user_id,
      metadata: message.metadata
    }
  end

  def expanded(%{customer: %ChatApi.Customers.Customer{}} = message) do
    %{
      id: message.id,
      object: "message",
      body: message.body,
      type: message.type,
      content_type: message.content_type,
      private: message.private,
      source: message.source,
      created_at: message.inserted_at,
      sent_at: message.sent_at,
      seen_at: message.seen_at,
      conversation_id: message.conversation_id,
      account_id: message.account_id,
      user_id: message.user_id,
      user: maybe(message.user, &UserJSON.user/1),
      customer_id: message.customer_id,
      customer: CustomerJSON.basic(message.customer),
      attachments: render_attachments(message.attachments),
      metadata: message.metadata
    }
  end

  def expanded(message) do
    %{
      id: message.id,
      object: "message",
      body: message.body,
      type: message.type,
      content_type: message.content_type,
      private: message.private,
      source: message.source,
      created_at: message.inserted_at,
      sent_at: message.sent_at,
      seen_at: message.seen_at,
      conversation_id: message.conversation_id,
      account_id: message.account_id,
      customer_id: message.customer_id,
      user_id: message.user_id,
      user: maybe(message.user, &UserJSON.user/1),
      attachments: render_attachments(message.attachments),
      metadata: message.metadata
    }
  end

  # TODO: figure out the best way to handle this idiomatically
  defp render_attachments([_ | _] = attachments),
    do: Enum.map(attachments, &FileJSON.file/1)

  defp render_attachments(_attachments), do: []
end
