defmodule ChatApiWeb.ConversationJSON do
  import ChatApiWeb.JSONHelpers

  alias ChatApiWeb.{
    MentionJSON,
    MessageJSON,
    CustomerJSON,
    TagJSON
  }

  def index(%{conversations: conversations, pagination: pagination}) do
    %{
      data: Enum.map(conversations, &expanded/1),
      next: pagination.after,
      previous: pagination.before,
      limit: pagination.limit,
      total: pagination.total_count
    }
  end

  def index(%{conversations: conversations}) do
    %{data: Enum.map(conversations, &expanded/1)}
  end

  def create(%{conversation: conversation}) do
    %{data: maybe(conversation, &basic/1)}
  end

  def update(%{conversation: conversation}) do
    %{data: maybe(conversation, &basic/1)}
  end

  def show(%{conversation: conversation}) do
    %{data: maybe(conversation, &expanded/1)}
  end

  def basic(conversation) do
    %{
      id: conversation.id,
      object: "conversation",
      source: conversation.source,
      created_at: conversation.inserted_at,
      closed_at: conversation.closed_at,
      last_activity_at: conversation.last_activity_at,
      status: conversation.status,
      read: conversation.read,
      priority: conversation.priority,
      subject: conversation.subject,
      account_id: conversation.account_id,
      customer_id: conversation.customer_id,
      assignee_id: conversation.assignee_id,
      inbox_id: conversation.inbox_id,
      metadata: conversation.metadata
    }
  end

  def expanded(conversation) do
    %{
      id: conversation.id,
      object: "conversation",
      source: conversation.source,
      created_at: conversation.inserted_at,
      closed_at: conversation.closed_at,
      last_activity_at: conversation.last_activity_at,
      status: conversation.status,
      read: conversation.read,
      priority: conversation.priority,
      subject: conversation.subject,
      account_id: conversation.account_id,
      customer_id: conversation.customer_id,
      assignee_id: conversation.assignee_id,
      inbox_id: conversation.inbox_id,
      metadata: conversation.metadata,
      customer: maybe(conversation.customer, &CustomerJSON.customer/1),
      messages: Enum.map(conversation.messages, &MessageJSON.expanded/1),
      tags: render_tags(conversation.tags),
      mentions: render_mentions(conversation.mentions)
    }
  end

  defp render_tags([_ | _] = tags) do
    Enum.map(tags, &TagJSON.tag/1)
  end

  defp render_tags(_tags), do: []

  defp render_mentions([_ | _] = mentions) do
    Enum.map(mentions, &MentionJSON.mention/1)
  end

  defp render_mentions(_mentions), do: []
end
