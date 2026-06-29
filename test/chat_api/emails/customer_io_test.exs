defmodule ChatApi.Emails.CustomerIOTest do
  use ExUnit.Case, async: true
  import Tesla.Mock

  alias ChatApi.Emails.CustomerIO

  describe "when disabled (no API key)" do
    setup do
      System.delete_env("CUSTOMER_IO_API_KEY")
      :ok
    end

    test "identify/2 is a no-op returning {:ok, _}" do
      assert {:ok, _} = CustomerIO.identify("user-1", %{email: "a@b.com"})
    end

    test "track/3 is a no-op returning {:ok, _}" do
      assert {:ok, _} = CustomerIO.track("user-1", "sign_up", %{})
    end
  end

  describe "when enabled" do
    setup do
      System.put_env("CUSTOMER_IO_SITE_ID", "site")
      System.put_env("CUSTOMER_IO_API_KEY", "key")

      on_exit(fn ->
        System.delete_env("CUSTOMER_IO_SITE_ID")
        System.delete_env("CUSTOMER_IO_API_KEY")
      end)

      :ok
    end

    test "identify/2 PUTs to the customer endpoint" do
      mock(fn
        %{method: :put, url: "https://track.customer.io/api/v1/customers/user-1"} ->
          %Tesla.Env{status: 200, body: ""}
      end)

      assert {:ok, _} = CustomerIO.identify("user-1", %{email: "a@b.com"})
    end

    test "track/3 POSTs an event with name + data" do
      mock(fn
        %{
          method: :post,
          url: "https://track.customer.io/api/v1/customers/user-1/events",
          body: body
        } ->
          assert body =~ "sign_up"
          %Tesla.Env{status: 200, body: ""}
      end)

      assert {:ok, _} = CustomerIO.track("user-1", "sign_up", %{plan: "free"})
    end
  end
end
