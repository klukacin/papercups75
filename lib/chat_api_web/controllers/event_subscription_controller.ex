defmodule ChatApiWeb.EventSubscriptionController do
  use ChatApiWeb, :controller

  alias ChatApi.Accounts
  alias ChatApi.EventSubscriptions
  alias ChatApi.EventSubscriptions.EventSubscription

  action_fallback ChatApiWeb.FallbackController

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn) do
      event_subscriptions = EventSubscriptions.list_event_subscriptions(account_id)
      render(conn, :index, event_subscriptions: event_subscriptions)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"event_subscription" => event_subscription_params}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         params <- Map.merge(event_subscription_params, %{"account_id" => account_id}),
         {:ok, %EventSubscription{} = event_subscription} <-
           EventSubscriptions.create_event_subscription(params) do
      # Not sure the most appropriate place to handle this verification :shrug:
      verified =
        event_subscription
        |> Map.get(:webhook_url)
        |> EventSubscriptions.is_valid_webhook_url?()

      {:ok, result} =
        EventSubscriptions.update_event_subscription(event_subscription, %{verified: verified})

      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.event_subscription_path(conn, :show, result)
      )
      |> render(:show, event_subscription: result)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %EventSubscription{} = event_subscription <- authorize(id, account_id) do
      render(conn, :show, event_subscription: event_subscription)
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id, "event_subscription" => event_subscription_params}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %EventSubscription{} = event_subscription <- authorize(id, account_id) do
      # Not sure the most appropriate place to handle this verification :shrug:
      verified =
        event_subscription_params
        |> Map.get("webhook_url")
        |> EventSubscriptions.is_valid_webhook_url?()

      # `account_id` is forced from the resolved account so an update can never
      # move the subscription into another workspace.
      params =
        event_subscription_params
        |> Map.merge(%{"verified" => verified, "account_id" => account_id})

      with {:ok, %EventSubscription{} = event_subscription} <-
             EventSubscriptions.update_event_subscription(event_subscription, params) do
        render(conn, :show, event_subscription: event_subscription)
      end
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %EventSubscription{} = event_subscription <- authorize(id, account_id),
         {:ok, %EventSubscription{}} <-
           EventSubscriptions.delete_event_subscription(event_subscription) do
      send_resp(conn, :no_content, "")
    end
  end

  # Loads the subscription only if it belongs to the resolved account, so a
  # user cannot read/modify/delete another workspace's webhook config by id.
  @spec authorize(binary(), binary()) :: EventSubscription.t() | {:error, :not_found}
  defp authorize(id, account_id) do
    case EventSubscriptions.get_event_subscription!(id) do
      %EventSubscription{account_id: ^account_id} = event_subscription -> event_subscription
      _ -> {:error, :not_found}
    end
  end

  @spec verify(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def verify(conn, %{"url" => url}) do
    verified = EventSubscriptions.is_valid_webhook_url?(url)

    json(conn, %{
      data: %{
        verified: verified
      }
    })
  end
end
