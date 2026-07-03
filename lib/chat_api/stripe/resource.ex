defmodule ChatApi.Stripe.Resource do
  @moduledoc """
  Maps raw Stripe JSON (string-keyed maps) into the typed, atom-keyed maps that
  this application's callers and views expect.

  Structural fields use atom keys so that dot-access (`resource.id`,
  `subscription.items.data`) works. `metadata` is deliberately kept as a
  STRING-keyed map so that `metadata["name"]` keeps working.
  """

  @doc "Wrap a Stripe list response (`%{\"object\" => \"list\", \"data\" => [...]}`)."
  @spec list(map(), (map() -> map())) :: %{object: binary(), data: [map()]}
  def list(raw, mapper) do
    data = raw["data"] || []
    %{object: "list", data: Enum.map(data, mapper)}
  end

  @spec subscription(map() | nil) :: map() | nil
  def subscription(nil), do: nil

  def subscription(raw) do
    %{
      id: raw["id"],
      object: "subscription",
      customer: raw["customer"],
      livemode: raw["livemode"],
      start_date: raw["start_date"],
      status: raw["status"],
      current_period_start: raw["current_period_start"],
      current_period_end: raw["current_period_end"],
      trial_start: raw["trial_start"],
      trial_end: raw["trial_end"],
      days_until_due: raw["days_until_due"],
      quantity: raw["quantity"],
      metadata: raw["metadata"] || %{},
      discount: discount(raw["discount"]),
      items: %{
        object: "list",
        data: raw |> subscription_items() |> Enum.map(&subscription_item/1)
      }
    }
  end

  defp subscription_items(raw), do: get_in(raw, ["items", "data"]) || []

  defp subscription_item(item) do
    %{
      id: item["id"],
      object: "subscription_item",
      quantity: item["quantity"],
      price: price(item["price"])
    }
  end

  @spec product(map() | nil) :: map() | nil
  def product(nil), do: nil

  def product(raw) do
    %{
      id: raw["id"],
      object: "product",
      name: raw["name"],
      active: raw["active"],
      # Kept string-keyed on purpose: callers/views use metadata["name"].
      metadata: raw["metadata"] || %{}
    }
  end

  @spec price(map() | nil) :: map() | nil
  def price(nil), do: nil

  def price(raw) do
    %{
      id: raw["id"],
      object: "price",
      active: raw["active"],
      unit_amount: raw["unit_amount"],
      currency: raw["currency"],
      amount_decimal: raw["amount_decimal"],
      created: raw["created"],
      billing_scheme: raw["billing_scheme"],
      product: raw["product"],
      metadata: raw["metadata"] || %{},
      recurring: recurring(raw["recurring"])
    }
  end

  defp recurring(nil), do: %{interval: nil, interval_count: nil}

  defp recurring(raw),
    do: %{interval: raw["interval"], interval_count: raw["interval_count"]}

  @spec payment_method(map() | nil) :: map() | nil
  def payment_method(nil), do: nil

  def payment_method(raw) do
    %{
      id: raw["id"],
      object: "payment_method",
      customer: raw["customer"],
      card: card(raw["card"])
    }
  end

  defp card(nil), do: %{brand: nil, country: nil, exp_month: nil, exp_year: nil, last4: nil}

  defp card(raw) do
    %{
      brand: raw["brand"],
      country: raw["country"],
      exp_month: raw["exp_month"],
      exp_year: raw["exp_year"],
      last4: raw["last4"]
    }
  end

  @spec customer(map() | nil) :: map() | nil
  def customer(nil), do: nil

  def customer(raw) do
    %{
      id: raw["id"],
      object: "customer",
      name: raw["name"],
      email: raw["email"],
      metadata: raw["metadata"] || %{}
    }
  end

  defp discount(nil), do: nil

  defp discount(raw) do
    %{id: raw["id"], object: "discount", coupon: coupon(raw["coupon"])}
  end

  defp coupon(nil), do: nil

  defp coupon(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      livemode: raw["livemode"],
      duration: raw["duration"],
      duration_in_months: raw["duration_in_months"],
      percent_off: raw["percent_off"],
      amount_off: raw["amount_off"],
      currency: raw["currency"],
      valid: raw["valid"],
      redeem_by: raw["redeem_by"],
      times_redeemed: raw["times_redeemed"]
    }
  end
end
