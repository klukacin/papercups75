defmodule Stripe.Price do
  @moduledoc """
  Minimal Stripe Prices API wrapper backed by `ChatApi.Stripe.Http`.
  """

  alias ChatApi.Stripe.{Http, Resource}

  @type t :: map()

  @spec list(map()) :: {:ok, %{data: [t()]}} | {:error, Stripe.Error.t()}
  def list(params \\ %{}) do
    "/prices" |> Http.get(params) |> Http.map(fn raw -> Resource.list(raw, &Resource.price/1) end)
  end
end
