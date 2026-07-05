defmodule ChatApiWeb.TagJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{tags: tags}) do
    %{data: Enum.map(tags, &tag/1)}
  end

  def show(%{tag: tag}) do
    %{data: maybe(tag, &tag/1)}
  end

  def tag(tag) do
    %{
      id: tag.id,
      object: "tag",
      created_at: tag.inserted_at,
      updated_at: tag.updated_at,
      name: tag.name,
      description: tag.description,
      color: tag.color
    }
  end
end
