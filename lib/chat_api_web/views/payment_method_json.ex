defmodule ChatApiWeb.PaymentMethodJSON do
  import ChatApiWeb.JSONHelpers

  def show(%{payment_method: payment_method}) do
    %{data: maybe(payment_method, &payment_method/1)}
  end

  def payment_method(payment_method) do
    %{
      id: payment_method.id,
      object: "payment_method",
      customer: payment_method.customer,
      brand: payment_method.card.brand,
      country: payment_method.card.country,
      exp_month: payment_method.card.exp_month,
      exp_year: payment_method.card.exp_year,
      last4: payment_method.card.last4
    }
  end
end
