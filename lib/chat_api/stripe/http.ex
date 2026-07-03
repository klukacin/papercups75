defmodule ChatApi.Stripe.Http do
  @moduledoc """
  Thin Tesla/Finch HTTP client for the Stripe REST API.

  This replaces the `stripity_stripe` dependency (which pulled in `hackney`).
  It talks to `https://api.stripe.com/v1` using Bearer auth and Stripe's
  `application/x-www-form-urlencoded` deep-object body encoding.

  All requests return `{:ok, raw_map}` (Stripe JSON decoded to a string-keyed
  map) or `{:error, %Stripe.Error{}}`. Higher-level modules (`Stripe.Subscription`,
  `Stripe.Product`, ...) map the raw map into typed atom-keyed maps via
  `ChatApi.Stripe.Resource`.
  """

  @base_url "https://api.stripe.com/v1"

  @doc "GET request. `query` may be a flat map or keyword list."
  @spec get(binary(), map() | keyword()) :: {:ok, map()} | {:error, Stripe.Error.t()}
  def get(path, query \\ []), do: request(:get, path, query: normalize_query(query))

  @doc "POST request. `body` is a (possibly nested) map, form-encoded for Stripe."
  @spec post(binary(), map()) :: {:ok, map()} | {:error, Stripe.Error.t()}
  def post(path, body \\ %{}), do: request(:post, path, body: body)

  @doc "DELETE request."
  @spec delete(binary()) :: {:ok, map()} | {:error, Stripe.Error.t()}
  def delete(path), do: request(:delete, path, [])

  @doc """
  Apply `fun` to the raw map of a successful result, passing errors through.

      Http.get("/products/\#{id}") |> Http.map(&Resource.product/1)
  """
  @spec map({:ok, map()} | {:error, Stripe.Error.t()}, (map() -> any())) ::
          {:ok, any()} | {:error, Stripe.Error.t()}
  def map({:ok, raw}, fun), do: {:ok, fun.(raw)}
  def map({:error, _} = error, _fun), do: error

  # --- Request pipeline -----------------------------------------------------

  defp request(method, path, opts) do
    tesla_opts =
      [method: method, url: path, query: Keyword.get(opts, :query, [])]
      |> maybe_put_body(Keyword.get(opts, :body))

    case Tesla.request(client(), tesla_opts) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, decode(body)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, build_error(status, decode(body))}

      {:error, reason} ->
        {:error,
         %Stripe.Error{
           source: :network,
           message: "Stripe request failed: #{inspect(reason)}",
           user_message: "Unable to reach Stripe. Please try again.",
           extra: %{http_status: 502, reason: reason}
         }}
    end
  end

  defp maybe_put_body(opts, nil), do: opts

  defp maybe_put_body(opts, body) do
    Keyword.merge(opts,
      body: encode_body(body),
      headers: [{"content-type", "application/x-www-form-urlencoded"}]
    )
  end

  defp client do
    # No adapter is specified here on purpose: it is resolved from the global
    # `config :tesla, adapter: ...` (Finch in dev/prod, Tesla.Mock in test).
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer " <> api_key()}]}
    ])
  end

  defp api_key, do: Application.get_env(:chat_api, :stripe_api_key) || ""

  defp normalize_query(query) when is_map(query), do: Map.to_list(query)
  defp normalize_query(query) when is_list(query), do: query
  defp normalize_query(_), do: []

  # --- Response decoding ----------------------------------------------------

  @doc false
  def decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  # Tesla.Mock (test env) may hand back an already-decoded map.
  def decode(body) when is_map(body), do: body
  def decode(_), do: %{}

  defp build_error(status, %{"error" => error}) when is_map(error) do
    %Stripe.Error{
      type: error["type"],
      code: error["code"],
      message: error["message"],
      user_message: error["message"] || "Stripe returned an error.",
      request_id: error["request_id"],
      source: :stripe,
      extra: %{http_status: status, raw_error: error}
    }
  end

  defp build_error(status, body) do
    %Stripe.Error{
      source: :stripe,
      message: "Stripe API error (HTTP #{status})",
      user_message: "Stripe returned an error.",
      extra: %{http_status: status, raw_error: body}
    }
  end

  # --- Stripe form encoding -------------------------------------------------
  #
  # Stripe does NOT accept JSON request bodies. Bodies must be
  # application/x-www-form-urlencoded using deep-object bracket notation:
  #
  #   %{invoice_settings: %{default_payment_method: "pm_123"}}
  #     -> "invoice_settings[default_payment_method]=pm_123"
  #
  #   %{items: [%{price: "p_1"}, %{id: "si_1", deleted: true}]}
  #     -> "items[0][price]=p_1&items[1][id]=si_1&items[1][deleted]=true"
  #
  #   %{trial_period_days: 14} -> "trial_period_days=14"

  @doc """
  Encode a (possibly nested) map/list into a Stripe form-urlencoded body string.
  """
  @spec encode_body(map() | list()) :: binary()
  def encode_body(data) do
    data
    |> flatten_pairs()
    |> Enum.map_join("&", fn {key, value} ->
      URI.encode_www_form(key) <> "=" <> URI.encode_www_form(value)
    end)
  end

  @doc """
  Flatten a nested map/list into an ordered list of `{bracket_key, string_value}`
  pairs using Stripe's deep-object notation.
  """
  @spec flatten_pairs(map() | list()) :: [{binary(), binary()}]
  def flatten_pairs(data), do: do_flatten(nil, data)

  defp do_flatten(prefix, map) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      do_flatten(compose_key(prefix, to_string(key)), value)
    end)
  end

  defp do_flatten(prefix, list) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      do_flatten(compose_key(prefix, Integer.to_string(index)), value)
    end)
  end

  defp do_flatten(prefix, value), do: [{prefix, to_string(value)}]

  defp compose_key(nil, key), do: key
  defp compose_key(prefix, key), do: "#{prefix}[#{key}]"
end
