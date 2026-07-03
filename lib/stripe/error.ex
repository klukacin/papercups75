defmodule Stripe.Error do
  @moduledoc """
  Error struct returned by the in-repo Stripe client.

  Mirrors the subset of the `stripity_stripe` `Stripe.Error` struct that this
  application relies on. In particular callers read `error.user_message` and
  `error.extra.http_status` (see `ChatApiWeb.PaymentMethodController`).
  """

  @type t :: %__MODULE__{
          type: atom() | binary() | nil,
          code: binary() | nil,
          message: binary() | nil,
          user_message: binary() | nil,
          request_id: binary() | nil,
          source: atom() | nil,
          extra: map()
        }

  defstruct type: nil,
            code: nil,
            message: nil,
            user_message: nil,
            request_id: nil,
            source: nil,
            extra: %{}
end
