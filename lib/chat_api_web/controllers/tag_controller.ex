defmodule ChatApiWeb.TagController do
  use ChatApiWeb, :controller

  alias ChatApi.Accounts
  alias ChatApi.Tags
  alias ChatApi.Tags.Tag

  action_fallback(ChatApiWeb.FallbackController)

  plug(:authorize when action in [:show, :update, :delete])

  defp authorize(conn, _) do
    id = conn.path_params["id"]

    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         tag = %{account_id: ^account_id} <- Tags.get_tag!(id) do
      assign(conn, :current_tag, tag)
    else
      _ -> ChatApiWeb.FallbackController.call(conn, {:error, :not_found}) |> halt()
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    account_id = Accounts.get_current_account_id(conn)
    tags = Tags.list_tags(account_id)

    render(conn, :index, tags: tags)
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(%{assigns: %{current_user: %{id: creator_id}}} = conn, %{
        "tag" => tag_params
      }) do
    account_id = Accounts.get_current_account_id(conn)

    with {:ok, %Tag{} = tag} <-
           tag_params
           |> Map.merge(%{"creator_id" => creator_id, "account_id" => account_id})
           |> Tags.create_tag() do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.tag_path(conn, :show, tag))
      |> render(:show, tag: tag)
    end
  end

  def show(conn, _params) do
    render(conn, :show, tag: conn.assigns.current_tag)
  end

  def update(conn, %{"tag" => tag_params}) do
    with {:ok, %Tag{} = tag} <- Tags.update_tag(conn.assigns.current_tag, tag_params) do
      render(conn, :show, tag: tag)
    end
  end

  def delete(conn, _params) do
    with {:ok, %Tag{}} <- Tags.delete_tag(conn.assigns.current_tag) do
      send_resp(conn, :no_content, "")
    end
  end
end
