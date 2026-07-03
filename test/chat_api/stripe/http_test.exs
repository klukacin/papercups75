defmodule ChatApi.Stripe.HttpTest do
  use ExUnit.Case, async: true
  import Tesla.Mock

  alias ChatApi.Stripe.Http

  describe "flatten_pairs/1 and encode_body/1 (Stripe deep-object form encoding)" do
    test "encodes scalars" do
      assert Http.flatten_pairs(%{trial_period_days: 14}) == [{"trial_period_days", "14"}]
      assert Http.encode_body(%{trial_period_days: 14}) == "trial_period_days=14"
      assert Http.encode_body(%{active: true}) == "active=true"
    end

    test "encodes nested maps with bracket notation" do
      body = %{invoice_settings: %{default_payment_method: "pm_123"}}

      assert Http.flatten_pairs(body) ==
               [{"invoice_settings[default_payment_method]", "pm_123"}]

      # Brackets are www-form-encoded (%5B / %5D)
      assert Http.encode_body(body) ==
               "invoice_settings%5Bdefault_payment_method%5D=pm_123"
    end

    test "encodes arrays of maps with indexed bracket notation" do
      body = %{items: [%{price: "price_123"}, %{id: "si_1", deleted: true}]}

      pairs = Http.flatten_pairs(body)

      assert {"items[0][price]", "price_123"} in pairs
      assert {"items[1][id]", "si_1"} in pairs
      assert {"items[1][deleted]", "true"} in pairs

      encoded = Http.encode_body(body)
      assert encoded =~ "items%5B0%5D%5Bprice%5D=price_123"
      assert encoded =~ "items%5B1%5D%5Bid%5D=si_1"
      assert encoded =~ "items%5B1%5D%5Bdeleted%5D=true"
    end

    test "url-encodes special characters in values" do
      assert Http.encode_body(%{name: "Acme & Co"}) == "name=Acme+%26+Co"
    end
  end

  describe "request success path" do
    test "GET decodes a JSON body into a string-keyed map" do
      mock(fn
        %{method: :get, url: "https://api.stripe.com/v1/products/prod_1"} = env ->
          # Auth header is set from config :chat_api, :stripe_api_key
          assert Enum.any?(env.headers, fn {k, v} ->
                   k == "authorization" and String.starts_with?(v, "Bearer ")
                 end)

          %Tesla.Env{status: 200, body: ~s({"id":"prod_1","object":"product"})}
      end)

      assert {:ok, %{"id" => "prod_1"}} = Http.get("/products/prod_1")
    end

    test "POST form-encodes the body and sets the content-type header" do
      mock(fn
        %{method: :post, url: "https://api.stripe.com/v1/customers", body: body} = env ->
          assert body =~ "name=Acme"
          assert body =~ "email=a%40b.com"

          assert {"content-type", "application/x-www-form-urlencoded"} in env.headers

          %Tesla.Env{status: 200, body: %{"id" => "cus_1"}}
      end)

      assert {:ok, %{"id" => "cus_1"}} =
               Http.post("/customers", %{name: "Acme", email: "a@b.com"})
    end
  end

  describe "request error path" do
    test "maps a Stripe error body to %Stripe.Error{} with http_status" do
      mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 402,
            body: %{
              "error" => %{
                "type" => "card_error",
                "code" => "card_declined",
                "message" => "Your card was declined."
              }
            }
          }
      end)

      assert {:error, error} = Http.get("/payment_methods/pm_x")
      assert %Stripe.Error{} = error
      assert error.type == "card_error"
      assert error.code == "card_declined"
      assert error.message == "Your card was declined."
      assert error.user_message == "Your card was declined."
      assert error.extra.http_status == 402
    end

    test "maps a transport error to %Stripe.Error{}" do
      mock(fn _ -> {:error, :econnrefused} end)

      assert {:error, %Stripe.Error{} = error} = Http.get("/products/x")
      assert error.source == :network
      assert error.message =~ "econnrefused"
    end
  end
end
