defmodule ChatApi.Emails.CustomerIO do
  @moduledoc """
  A module to handle email automation with customer.io.

  Talks to the Customer.io Track API directly over Tesla (Finch adapter) rather
  than the unmaintained `customerio` Hex package, which pinned an old hackney.
  """

  alias ChatApi.Users
  require Logger

  @base_url "https://track.customer.io/api/v1"

  # TODO: how should we handled disabled/archived users?

  @spec handle_registration_event(any(), any()) :: boolean()
  def handle_registration_event(user, company_name) do
    case Users.validate_email(user) do
      {:ok, %Users.User{has_valid_email: true} = user} ->
        save_new_signup(user, company_name)

      _ ->
        Logger.warn("Unable to validate user's email. Skipping save to Customer IO.")

        false
    end
  end

  @spec identify(any(), map()) :: {:ok, any()} | {:error, any()}
  def identify(user_id, attrs \\ %{}) do
    if enabled?() do
      client()
      |> Tesla.put("/customers/#{URI.encode(to_string(user_id))}", attrs)
      |> handle_response()
    else
      log_disabled("identified user #{inspect(user_id)} with data: #{inspect(attrs)}")
    end
  end

  @spec track(any(), binary(), map()) :: {:ok, any()} | {:error, any()}
  def track(user_id, event, attrs \\ %{}) do
    if enabled?() do
      client()
      |> Tesla.post("/customers/#{URI.encode(to_string(user_id))}/events", %{
        name: event,
        data: attrs
      })
      |> handle_response()
    else
      log_disabled(
        "tracked event #{inspect(event)} for user #{inspect(user_id)} with data: #{inspect(attrs)}"
      )
    end
  end

  @spec enabled?() :: boolean()
  def enabled?() do
    case System.get_env("CUSTOMER_IO_API_KEY") do
      key when is_binary(key) -> String.length(key) > 0
      _ -> false
    end
  end

  defp client() do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.BasicAuth,
       username: System.get_env("CUSTOMER_IO_SITE_ID") || "",
       password: System.get_env("CUSTOMER_IO_API_KEY") || ""}
    ])
  end

  defp handle_response({:ok, %Tesla.Env{status: status} = env}) when status in 200..299,
    do: {:ok, env}

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}),
    do: {:error, %{status: status, body: body}}

  defp handle_response({:error, reason}), do: {:error, reason}

  defp log_disabled(message) do
    Logger.info("[Customer IO] Would have #{message}")

    {:ok, message}
  end

  @spec format_user(Users.User.t(), binary(), integer()) :: map()
  defp format_user(user, company_name, now) do
    %{
      # User fields
      id: user.id,
      email: user.email,
      account_id: user.account_id,
      role: user.role,
      # Account fields
      company_name: company_name,
      # Timestamps
      created_at: now,
      updated_at: now
    }
  end

  @spec save_new_signup(Users.User.t(), binary()) :: boolean()
  defp save_new_signup(user, company_name) do
    now = :os.system_time(:seconds)

    with {:ok, _} <-
           identify(user.id, format_user(user, company_name, now)),
         {:ok, _} <- track(user.id, "sign_up", %{signed_up_at: now}) do
      Logger.debug("Successfully added user to customer.io")

      true
    else
      error ->
        Logger.error("Something went wrong with customer.io: #{inspect(error)}")

        false
    end
  end
end
