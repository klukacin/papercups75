defmodule ChatApi.StripeClient do
  @moduledoc """
  The StripeClient context.
  """

  import Ecto.Query, warn: false
  alias ChatApi.{Accounts, Repo}
  alias ChatApi.Accounts.Account

  require Logger

  @spec enabled? :: boolean()
  def enabled?() do
    case System.get_env("PAPERCUPS_STRIPE_SECRET") do
      "sk_" <> _rest -> true
      _ -> false
    end
  end

  @spec add_payment_method(
          binary(),
          binary(),
          binary()
        ) ::
          {:ok, Stripe.PaymentMethod.t()} | {:error, Stripe.Error.t()}
  @doc """
  Add a payment method to an account via Stripe
  """
  def add_payment_method(nil, _payment_method_id, _account_id) do
    {:error,
     %Stripe.Error{
       source: :client,
       message: "No Stripe customer for account",
       user_message: "Billing is not set up for this account.",
       extra: %{http_status: 400}
     }}
  end

  def add_payment_method(customer_id, payment_method_id, account_id) do
    # Only persist the local default payment method once Stripe has actually
    # attached it and updated the customer; otherwise a Stripe failure would
    # leave the DB pointing at a payment method that was never attached.
    with {:ok, payment_method} <-
           Stripe.PaymentMethod.attach(%{
             payment_method: payment_method_id,
             customer: customer_id
           }),
         {:ok, _customer} <-
           Stripe.Customer.update(customer_id, %{
             invoice_settings: %{default_payment_method: payment_method_id}
           }) do
      Account
      |> Repo.get!(account_id)
      |> Accounts.update_billing_info(%{stripe_default_payment_method_id: payment_method_id})

      {:ok, payment_method}
    end
  end

  @spec find_or_create_customer(binary(), map()) :: binary() | nil
  @doc """
  Find or create the Stripe customer token for the given account
  """
  def find_or_create_customer(account_id, user) do
    case Repo.get!(Account, account_id) do
      %{company_name: name, stripe_customer_id: nil} = account ->
        case Stripe.Customer.create(%{name: name, email: user.email}) do
          {:ok, customer} ->
            Accounts.update_billing_info(account, %{stripe_customer_id: customer.id})
            customer.id

          {:error, error} ->
            Logger.error("Failed to create Stripe customer: #{inspect(error)}")
            nil
        end

      %{stripe_customer_id: customer_id} ->
        customer_id

      _account ->
        nil
    end
  end
end
