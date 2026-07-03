defmodule Stripe.Customer do
  @moduledoc """
  Minimal Stripe Customers API wrapper backed by `ChatApi.Stripe.Http`.
  """

  alias ChatApi.Stripe.{Http, Resource}

  @type t :: map()

  @spec create(map()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def create(params) do
    "/customers" |> Http.post(params) |> Http.map(&Resource.customer/1)
  end

  @spec update(binary(), map()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def update(id, params) do
    "/customers/#{id}" |> Http.post(params) |> Http.map(&Resource.customer/1)
  end
end
