defmodule ChatApi.ExAwsHttpClient do
  @moduledoc """
  ExAws HTTP client backed by Tesla (Finch adapter), replacing the default
  hackney client so AWS (S3/SES/Lambda) traffic no longer depends on hackney.
  """

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, _http_opts) do
    # Empty middleware + the globally configured Tesla adapter (Finch in prod,
    # Tesla.Mock in tests). AWS request bodies/headers are already prepared and
    # signed by ExAws, so no JSON/encoding middleware is applied here.
    case Tesla.request(Tesla.client([]),
           method: method,
           url: url,
           body: body,
           headers: headers
         ) do
      {:ok, %Tesla.Env{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status_code: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
