defmodule ChatApi.ExAwsHttpClientTest do
  use ExUnit.Case, async: true
  import Tesla.Mock

  alias ChatApi.ExAwsHttpClient

  test "maps a successful Tesla response to the ExAws shape" do
    mock(fn
      %{method: :get, url: "https://s3.amazonaws.com/bucket/key"} ->
        %Tesla.Env{status: 200, headers: [{"etag", "abc"}], body: "data"}
    end)

    assert {:ok, %{status_code: 200, headers: [{"etag", "abc"}], body: "data"}} =
             ExAwsHttpClient.request(:get, "https://s3.amazonaws.com/bucket/key", "", [], [])
  end

  test "maps a Tesla error to {:error, %{reason: ...}}" do
    mock(fn _ -> {:error, :timeout} end)

    assert {:error, %{reason: :timeout}} =
             ExAwsHttpClient.request(:get, "https://s3.amazonaws.com/x", "", [], [])
  end
end
