defmodule Stripe.Product do
  @moduledoc """
  Minimal Stripe Products API wrapper backed by `ChatApi.Stripe.Http`.
  """

  alias ChatApi.Stripe.{Http, Resource}

  @type t :: map()

  @spec retrieve(binary()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def retrieve(id) do
    "/products/#{id}" |> Http.get() |> Http.map(&Resource.product/1)
  end

  @spec list(map()) :: {:ok, %{data: [t()]}} | {:error, Stripe.Error.t()}
  def list(params \\ %{}) do
    "/products"
    |> Http.get(params)
    |> Http.map(fn raw -> Resource.list(raw, &Resource.product/1) end)
  end
end
