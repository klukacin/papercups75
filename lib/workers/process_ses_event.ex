defmodule ChatApi.Workers.ProcessSesEvent do
  use Oban.Worker, queue: :default

  require Logger

  alias ChatApi.{
    Aws,
    Customers,
    ForwardingAddresses
  }

  alias ChatApi.Conversations.Conversation
  alias ChatApi.Customers.Customer
  alias ChatApi.ForwardingAddresses.ForwardingAddress
  alias ChatApi.Messages.Message

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(
        %Oban.Job{
          args: %{
            "ses_message_id" => ses_message_id,
            "from_address" => from_address,
            "to_addresses" => to_addresses,
            "forwarded_to" => forwarded_to,
            "received_by" => received_by
          }
        } = job
      ) do
    Logger.info("Processing SES event: #{inspect(job)}")

    # TODO: what kind of retry-logic should we use here?
    process_event(%{
      ses_message_id: ses_message_id,
      from_address: from_address,
      to_addresses: to_addresses,
      forwarded_to: forwarded_to,
      received_by: received_by
    })

    :ok
  end

  def process_event(%{
        ses_message_id: ses_message_id,
        from_address: from_address,
        to_addresses: to_addresses,
        forwarded_to: forwarded_to,
        received_by: received_by
      }) do
    # TODO: should we first check the email to see if we can find
    # an existing thread based on the references header?
    # (e.g. check for a previous message where the email message ID matches?)
    addresses = [forwarded_to] ++ to_addresses ++ received_by

    case get_message_resource(addresses) do
      %Conversation{} = conversation ->
        IO.inspect(conversation, label: "Found conversation!")

        handle_existing_thread(conversation, %{
          ses_message_id: ses_message_id,
          from_address: from_address
        })

      %ForwardingAddress{} = forwarding_address ->
        IO.inspect(forwarding_address, label: "Found forwarding address!")

        handle_new_thread(forwarding_address, %{
          ses_message_id: ses_message_id,
          from_address: from_address
        })

      _ ->
        nil
    end
  end

  @spec handle_new_thread(ForwardingAddress.t(), map()) :: {:ok, Message.t()} | {:error, any()}
  def handle_new_thread(%ForwardingAddress{account_id: account_id, inbox_id: inbox_id}, %{
        ses_message_id: ses_message_id,
        from_address: from_address
      }) do
    with {:ok, email} <- Aws.retrieve_formatted_email(ses_message_id),
         IO.inspect(email, label: "Formatted email"),
         {:ok, %Customer{} = customer} <-
           Customers.find_or_create_by_email(from_address, account_id),
         IO.inspect(customer, label: "Customer"),
         {:ok, conversation} <-
           create_and_broadcast_conversation(%{
             account_id: account_id,
             inbox_id: inbox_id,
             customer_id: customer.id,
             subject: email.subject,
             # TODO: distinguish between gmail and SES?
             source: "email"
           }),
         IO.inspect(conversation, label: "Created conversation!") do
      create_and_broadcast_message(
        %{
          body: email.formatted_text,
          account_id: account_id,
          conversation_id: conversation.id,
          customer_id: customer.id,
          # TODO: distinguish between gmail and SES?
          source: "email",
          metadata: Aws.format_message_metadata(email),
          sent_at: DateTime.utc_now()
        },
        email.attachments
      )
    else
      error ->
        Logger.error("Something went wrong in `handle_new_thread/2`: #{inspect(error)}")

        error
    end
  end

  @spec handle_existing_thread(Conversation.t(), map()) :: {:ok, Message.t()} | {:error, any()}
  def handle_existing_thread(%Conversation{account_id: account_id} = conversation, %{
        ses_message_id: ses_message_id,
        from_address: from_address
      }) do
    with {:ok, email} <- Aws.retrieve_formatted_email(ses_message_id),
         IO.inspect(email, label: "Formatted email"),
         {:ok, %Customer{} = customer} <-
           Customers.find_or_create_by_email(from_address, account_id),
         IO.inspect(customer, label: "Customer") do
      create_and_broadcast_message(
        %{
          body: email.formatted_text,
          account_id: account_id,
          conversation_id: conversation.id,
          customer_id: customer.id,
          # TODO: distinguish between gmail and SES?
          source: "email",
          metadata: Aws.format_message_metadata(email),
          sent_at: DateTime.utc_now()
        },
        email.attachments
      )
    else
      error ->
        Logger.error("Something went wrong in `handle_existing_thread/2`: #{inspect(error)}")

        error
    end
  end

  # These creation helpers are channel-neutral and now live in
  # `ChatApi.EmailChannels` (shared with the generic IMAP email channel);
  # they are delegated here to keep this worker's public API intact.
  defdelegate create_and_broadcast_conversation(params), to: ChatApi.EmailChannels

  defdelegate create_and_broadcast_message(params, attachments \\ []), to: ChatApi.EmailChannels

  defdelegate process_email_attachment(attachment, message), to: ChatApi.EmailChannels

  defdelegate process_email_attachments(attachments, message), to: ChatApi.EmailChannels

  @spec find_forwarding_address(binary()) :: ForwardingAddress.t() | nil
  def find_forwarding_address(email) do
    domain = Application.get_env(:chat_api, :ses_forwarding_domain, "chat.papercups.io")

    if String.contains?(email, domain) do
      ForwardingAddresses.find_by_forwarding_email(email)
    else
      nil
    end
  end

  @spec is_reply_address?(binary() | nil) :: boolean()
  def is_reply_address?("reply+" <> _), do: true
  def is_reply_address?(_), do: false

  @spec find_conversation_by_address(binary()) :: Conversation.t() | nil
  def find_conversation_by_address(email) do
    case String.split(email, "@") do
      [name, _] ->
        case name do
          "reply+" <> conversation_id ->
            ChatApi.Conversations.get_conversation(conversation_id)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @spec get_message_resource([binary()], binary() | nil) ::
          Conversation.t() | ForwardingAddress.t() | nil
  def get_message_resource(email_addresses, nil),
    do: get_message_resource(email_addresses)

  def get_message_resource(email_addresses, forwarded_to_address) do
    # TODO: eventually we may want to verify that the `forwarded_to_address` and
    # the `to_addresses` have a valid match in the `forwarding_addresses` table
    get_message_resource([forwarded_to_address | email_addresses])
  end

  @spec get_message_resource([binary()]) :: Conversation.t() | ForwardingAddress.t() | nil
  def get_message_resource(email_addresses) do
    email_addresses
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while(nil, fn
      email, nil ->
        if is_reply_address?(email) do
          {:cont, find_conversation_by_address(email)}
        else
          {:cont, find_forwarding_address(email)}
        end

      _, %ForwardingAddress{} = acc ->
        {:halt, acc}

      _, %Conversation{} = acc ->
        {:halt, acc}
    end)
  end
end
