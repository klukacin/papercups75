defmodule ChatApiWeb.BillingJSON do
  import ChatApiWeb.JSONHelpers
  alias ChatApiWeb.PaymentMethodJSON

  def show(%{billing_info: billing_info}) do
    %{data: maybe(billing_info, &billing_info/1)}
  end

  def billing_info(billing_info) do
    %{
      payment_method: maybe(billing_info.payment_method, &PaymentMethodJSON.payment_method/1),
      subscription: maybe(billing_info.subscription, &subscription/1),
      product: maybe(billing_info.product, &product/1),
      subscription_plan: billing_info.subscription_plan,
      num_users: billing_info.num_users,
      num_messages: billing_info.num_messages
    }
  end

  def subscription(subscription) do
    %{
      id: subscription.id,
      livemode: subscription.livemode,
      start_date: subscription.start_date,
      status: subscription.status,
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      trial_start: subscription.trial_start,
      trial_end: subscription.trial_end,
      days_until_due: subscription.days_until_due,
      quantity: subscription.quantity,
      discount: maybe(subscription.discount, &discount/1),
      prices:
        subscription.items.data
        |> Enum.map(fn item -> item.price end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&price/1)
    }
  end

  def price(price) do
    %{
      id: price.id,
      active: price.active,
      unit_amount: price.unit_amount,
      currency: price.currency,
      amount_decimal: price.amount_decimal,
      created: price.created,
      billing_scheme: price.billing_scheme,
      interval: price.recurring.interval,
      interval_count: price.recurring.interval_count,
      product_id: price.product
    }
  end

  def product(product) do
    %{
      id: product.id,
      name: product.name,
      active: product.active,
      code: product.metadata["name"] || nil
    }
  end

  # Stripe may return a discount without a coupon; render nothing rather than
  # dereferencing `discount.coupon.id` on nil.
  def discount(%{coupon: nil}), do: nil

  def discount(discount) do
    %{
      id: discount.coupon.id,
      name: discount.coupon.name,
      livemode: discount.coupon.livemode,
      duration: discount.coupon.duration,
      duration_in_months: discount.coupon.duration_in_months,
      percent_off: discount.coupon.percent_off,
      amount_off: discount.coupon.amount_off,
      currency: discount.coupon.currency,
      valid: discount.coupon.valid,
      redeem_by: discount.coupon.redeem_by,
      times_redeemed: discount.coupon.times_redeemed
    }
  end
end
