defmodule ChatApi.Stripe.ErrorHandlingTest do
  @moduledoc """
  Regression tests for graceful Stripe error handling: a Stripe failure must
  surface as a mapped HTTP error, never a 500 (MatchError/BadMapError) or a
  silently-persisted local billing row.
  """
  use ChatApiWeb.ConnCase, async: true

  alias ChatApiWeb.FallbackController

  describe "StripeClient.add_payment_method/3 with no customer" do
    test "returns a 400 Stripe.Error instead of attaching against a nil customer" do
      assert {:error, %Stripe.Error{extra: %{http_status: 400}} = err} =
               ChatApi.StripeClient.add_payment_method(nil, "pm_123", "acc_123")

      assert err.user_message =~ "Billing"
    end
  end

  describe "FallbackController with a Stripe.Error" do
    test "maps the error to its http_status and user_message", %{conn: conn} do
      err = %Stripe.Error{
        user_message: "Card declined.",
        message: "raw stripe message",
        extra: %{http_status: 402}
      }

      conn = FallbackController.call(conn, {:error, err})

      assert %{"error" => %{"status" => 402, "message" => "Card declined."}} =
               json_response(conn, 402)
    end

    test "defaults to 502 when the error carries no http_status" do
      conn = FallbackController.call(build_conn(), {:error, %Stripe.Error{message: "boom"}})

      assert json_response(conn, 502)["error"]["status"] == 502
    end
  end
end
