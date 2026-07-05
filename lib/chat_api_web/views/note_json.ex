defmodule ChatApiWeb.NoteJSON do
  import ChatApiWeb.JSONHelpers

  alias ChatApiWeb.{
    CustomerJSON,
    UserJSON
  }

  alias ChatApi.Customers.Customer
  alias ChatApi.Users.User

  def index(%{notes: notes}) do
    %{data: Enum.map(notes, &note/1)}
  end

  def show(%{note: note}) do
    %{data: maybe(note, &note/1)}
  end

  def note(note) do
    %{
      id: note.id,
      object: "note",
      body: note.body,
      content_type: note.content_type,
      customer_id: note.customer_id,
      author_id: note.author_id,
      created_at: note.inserted_at,
      updated_at: note.updated_at
    }
    |> maybe_render_author(note)
    |> maybe_render_customer(note)
  end

  defp maybe_render_customer(json, %{customer: %Customer{} = customer}),
    do: Map.merge(json, %{customer: CustomerJSON.customer(customer)})

  defp maybe_render_customer(json, _), do: json

  defp maybe_render_author(json, %{author: author}) do
    case author do
      nil ->
        Map.merge(json, %{author: nil})

      %User{} = author ->
        Map.merge(json, %{author: UserJSON.user(author)})

      _ ->
        json
    end
  end
end
