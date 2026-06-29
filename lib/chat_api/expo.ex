defmodule ChatApi.Expo do
  @moduledoc """
  Minimal Expo push-notification client over Tesla (Finch adapter).

  Replaces the `exponent_server_sdk` Hex package, which depended on HTTPoison/
  hackney. Talks to the Expo push API: https://docs.expo.dev/push-notifications/
  """

  @base_url "https://exp.host/--/api/v2/push"

  @spec push(map()) :: {:ok, any()} | {:error, any()}
  def push(message) when is_map(message) do
    client()
    |> Tesla.post("/send", message)
    |> handle_response()
  end

  defp client() do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"accept", "application/json"}]}
    ])
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: %{"data" => data}}})
       when status in 200..299,
       do: {:ok, data}

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}),
    do: {:error, %{status: status, body: body}}

  defp handle_response({:error, reason}), do: {:error, reason}
end
