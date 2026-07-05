defmodule ChatApiWeb.EventSubscriptionJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{event_subscriptions: event_subscriptions}) do
    %{data: Enum.map(event_subscriptions, &event_subscription/1)}
  end

  def show(%{event_subscription: event_subscription}) do
    %{data: maybe(event_subscription, &event_subscription/1)}
  end

  def event_subscription(event_subscription) do
    %{
      id: event_subscription.id,
      object: "event_subscription",
      created_at: event_subscription.inserted_at,
      updated_at: event_subscription.updated_at,
      webhook_url: event_subscription.webhook_url,
      verified: event_subscription.verified,
      account_id: event_subscription.account_id,
      scope: event_subscription.scope
    }
  end
end
