defmodule ChatApi.ExpoTest do
  use ExUnit.Case, async: true
  import Tesla.Mock

  alias ChatApi.Expo

  test "push/1 POSTs the message to the Expo send endpoint and returns data" do
    mock(fn
      %{method: :post, url: "https://exp.host/--/api/v2/push/send", body: body} ->
        assert body =~ "ExponentPushToken"
        %Tesla.Env{status: 200, body: %{"data" => %{"status" => "ok", "id" => "abc"}}}
    end)

    assert {:ok, %{"status" => "ok"}} =
             Expo.push(%{to: "ExponentPushToken[xxx]", title: "Hi", body: "msg"})
  end

  test "push/1 returns an error tuple on non-2xx" do
    mock(fn
      %{method: :post} -> %Tesla.Env{status: 400, body: %{"errors" => ["bad"]}}
    end)

    assert {:error, %{status: 400}} = Expo.push(%{to: "x"})
  end
end
