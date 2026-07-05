defmodule ChatApiWeb.MentionJSON do
  import ChatApiWeb.JSONHelpers
  alias ChatApiWeb.UserJSON

  def index(%{mentions: mentions}) do
    %{data: Enum.map(mentions, &mention/1)}
  end

  def show(%{mention: mention}) do
    %{data: maybe(mention, &mention/1)}
  end

  def mention(mention) do
    %{
      id: mention.id,
      object: "mention",
      account_id: mention.account_id,
      created_at: mention.inserted_at,
      seen_at: mention.seen_at,
      conversation_id: mention.conversation_id,
      message_id: mention.message_id,
      user_id: mention.user_id,
      user: maybe(mention.user, &UserJSON.user/1)
    }
  end
end
