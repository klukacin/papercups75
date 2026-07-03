defmodule Stripe.Subscription do
  @moduledoc """
  Minimal Stripe Subscriptions API wrapper backed by `ChatApi.Stripe.Http`.
  """

  alias ChatApi.Stripe.{Http, Resource}

  @type t :: map()

  @spec retrieve(binary()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def retrieve(id) do
    "/subscriptions/#{id}" |> Http.get() |> Http.map(&Resource.subscription/1)
  end

  @spec create(map()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def create(params) do
    "/subscriptions" |> Http.post(params) |> Http.map(&Resource.subscription/1)
  end

  @spec update(binary(), map()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def update(id, params) do
    "/subscriptions/#{id}" |> Http.post(params) |> Http.map(&Resource.subscription/1)
  end

  @spec cancel(binary()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def cancel(id) do
    "/subscriptions/#{id}" |> Http.delete() |> Http.map(&Resource.subscription/1)
  end
end
