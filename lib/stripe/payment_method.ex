defmodule Stripe.PaymentMethod do
  @moduledoc """
  Minimal Stripe PaymentMethods API wrapper backed by `ChatApi.Stripe.Http`.
  """

  alias ChatApi.Stripe.{Http, Resource}

  @type t :: map()

  @spec retrieve(binary()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def retrieve(id) do
    "/payment_methods/#{id}" |> Http.get() |> Http.map(&Resource.payment_method/1)
  end

  @spec attach(%{payment_method: binary(), customer: binary()}) ::
          {:ok, t()} | {:error, Stripe.Error.t()}
  def attach(%{payment_method: payment_method_id, customer: customer_id}) do
    "/payment_methods/#{payment_method_id}/attach"
    |> Http.post(%{customer: customer_id})
    |> Http.map(&Resource.payment_method/1)
  end
end
