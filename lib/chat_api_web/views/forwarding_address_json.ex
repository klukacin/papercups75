defmodule ChatApiWeb.ForwardingAddressJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{forwarding_addresses: forwarding_addresses}) do
    %{data: Enum.map(forwarding_addresses, &forwarding_address/1)}
  end

  def show(%{forwarding_address: forwarding_address}) do
    %{data: maybe(forwarding_address, &forwarding_address/1)}
  end

  def forwarding_address(forwarding_address) do
    %{
      id: forwarding_address.id,
      object: "forwarding_address",
      forwarding_email_address: forwarding_address.forwarding_email_address,
      source_email_address: forwarding_address.source_email_address,
      state: forwarding_address.state,
      description: forwarding_address.description,
      account_id: forwarding_address.account_id,
      created_at: forwarding_address.inserted_at,
      updated_at: forwarding_address.updated_at
    }
  end
end
