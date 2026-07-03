defmodule ChatApi.Stripe.ClientTest do
  use ExUnit.Case, async: true
  import Tesla.Mock

  alias ChatApi.Stripe.Resource

  describe "Resource mapping" do
    test "subscription/1 maps id and items.data with full price objects" do
      raw = %{
        "id" => "sub_1",
        "object" => "subscription",
        "status" => "active",
        "items" => %{
          "object" => "list",
          "data" => [
            %{
              "id" => "si_1",
              "price" => %{
                "id" => "price_1",
                "unit_amount" => 1000,
                "recurring" => %{"interval" => "month", "interval_count" => 1}
              }
            }
          ]
        }
      }

      sub = Resource.subscription(raw)

      assert sub.id == "sub_1"
      assert sub.status == "active"
      assert [%{id: "si_1"} = item] = sub.items.data
      assert item.price.id == "price_1"
      assert item.price.unit_amount == 1000
      assert item.price.recurring.interval == "month"
    end

    test "subscription/1 returns nil for nil input" do
      assert Resource.subscription(nil) == nil
    end

    test "product/1 keeps metadata string-keyed" do
      product = Resource.product(%{"id" => "prod_1", "name" => "Team", "metadata" => %{"name" => "team"}})

      assert product.id == "prod_1"
      assert product.name == "Team"
      # metadata["name"] (string key) must still work
      assert product.metadata["name"] == "team"
    end

    test "list/2 wraps data in %{data: [...]} with atom key" do
      raw = %{"object" => "list", "data" => [%{"id" => "price_1"}, %{"id" => "price_2"}]}

      assert %{data: [%{id: "price_1"}, %{id: "price_2"}]} = Resource.list(raw, &Resource.price/1)
    end

    test "payment_method/1 maps card fields" do
      pm =
        Resource.payment_method(%{
          "id" => "pm_1",
          "customer" => "cus_1",
          "card" => %{"brand" => "visa", "last4" => "4242", "exp_month" => 12, "exp_year" => 2030}
        })

      assert pm.id == "pm_1"
      assert pm.customer == "cus_1"
      assert pm.card.brand == "visa"
      assert pm.card.last4 == "4242"
    end
  end

  describe "Stripe.* client functions over Tesla.Mock" do
    test "Stripe.Subscription.retrieve GETs and maps the response" do
      mock(fn
        %{method: :get, url: "https://api.stripe.com/v1/subscriptions/sub_1"} ->
          %Tesla.Env{
            status: 200,
            body: %{
              "id" => "sub_1",
              "items" => %{"data" => [%{"id" => "si_1", "price" => %{"id" => "price_1"}}]}
            }
          }
      end)

      assert {:ok, sub} = Stripe.Subscription.retrieve("sub_1")
      assert sub.id == "sub_1"
      assert [%{id: "si_1"}] = sub.items.data
    end

    test "Stripe.Subscription.create POSTs form-encoded nested items" do
      mock(fn
        %{method: :post, url: "https://api.stripe.com/v1/subscriptions", body: body} ->
          assert body =~ "customer=cus_1"
          assert body =~ "items%5B0%5D%5Bprice%5D=price_1"
          assert body =~ "trial_period_days=14"
          %Tesla.Env{status: 200, body: %{"id" => "sub_new"}}
      end)

      assert {:ok, %{id: "sub_new"}} =
               Stripe.Subscription.create(%{
                 customer: "cus_1",
                 items: [%{price: "price_1"}],
                 trial_period_days: 14
               })
    end

    test "Stripe.Product.list GETs with query and returns %{data: [...]}" do
      mock(fn
        %{method: :get, url: "https://api.stripe.com/v1/products", query: query} ->
          assert query == [active: true]

          %Tesla.Env{
            status: 200,
            body: %{
              "object" => "list",
              "data" => [%{"id" => "prod_1", "metadata" => %{"name" => "team"}}]
            }
          }
      end)

      assert {:ok, %{data: [product]}} = Stripe.Product.list(%{active: true})
      assert product.id == "prod_1"
      assert product.metadata["name"] == "team"
    end

    test "Stripe.Subscription.cancel issues a DELETE" do
      mock(fn
        %{method: :delete, url: "https://api.stripe.com/v1/subscriptions/sub_1"} ->
          %Tesla.Env{status: 200, body: %{"id" => "sub_1", "status" => "canceled"}}
      end)

      assert {:ok, %{id: "sub_1", status: "canceled"}} = Stripe.Subscription.cancel("sub_1")
    end
  end
end
