defmodule ChatApiWeb.InboxJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{inboxes: inboxes}) do
    %{data: Enum.map(inboxes, &inbox/1)}
  end

  def show(%{inbox: inbox}) do
    %{data: maybe(inbox, &inbox/1)}
  end

  def inbox(inbox) do
    %{
      id: inbox.id,
      object: "inbox",
      name: inbox.name,
      description: inbox.description,
      slug: inbox.slug,
      is_primary: inbox.is_primary,
      is_private: inbox.is_private,
      account_id: inbox.account_id
    }
  end
end
