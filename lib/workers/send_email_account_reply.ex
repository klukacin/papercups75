defmodule ChatApi.Workers.SendEmailAccountReply do
  @moduledoc """
  Sends an agent reply for an email-channel conversation through the
  per-inbox SMTP account (`ChatApi.EmailAccounts.EmailAccount`).

  Mirrors `ChatApi.Workers.SendSesReplyEmail`, but on the generic `email_*`
  metadata namespace and delivering through the account's own SMTP server
  (via `ChatApi.Mailers` with a per-delivery `Swoosh.Adapters.SMTP` config)
  instead of Amazon SES.

  The worker no-ops (returns `:ok`) unless all of the following hold:

    * the message was sent by an agent (has a `user`),
    * the conversation's inbox has an *active* `EmailAccount`,
    * some previous message in the conversation carries `email_*` metadata
      (i.e. the conversation actually flows through this channel — a
      conversation that only carries e.g. `ses_*` or `gmail_*` metadata must
      never trigger an SMTP send).

  Delivery failures return `{:error, reason}` so Oban retries (up to
  `max_attempts: 3`).
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  import Ecto.Query, warn: false

  require Logger

  alias ChatApi.{Accounts, Customers, EmailAccounts, Emails, Mailers, Messages, Repo}
  alias ChatApi.Conversations.Conversation
  alias ChatApi.Customers.Customer
  alias ChatApi.EmailAccounts.{Client, EmailAccount}
  alias ChatApi.Emails.Email
  alias ChatApi.Files.FileUpload
  alias ChatApi.Messages.Message
  alias ChatApi.Users.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    with %Message{user: %User{}} = message <- Messages.get_message!(message_id),
         %EmailAccount{status: "active"} = email_account <- find_email_account(message),
         %Message{metadata: %{"email_message_id" => _} = metadata} <-
           get_previous_email_message(message),
         to_address when is_binary(to_address) <-
           recipient_address(metadata, message.conversation) do
      send_email(message, email_account, metadata, to_address)
    else
      error ->
        Logger.info("[SendEmailAccountReply] Skipping SMTP reply: #{inspect(error)}")

        :ok
    end
  end

  @doc """
  Composes the threaded reply, delivers it through the email account's SMTP
  server and persists the sent message's threading metadata (mirrors the SES
  worker's persist step, on the `email_*` namespace).
  """
  @spec send_email(Message.t(), EmailAccount.t(), map(), String.t()) :: :ok | {:error, any()}
  def send_email(
        %Message{user: %User{} = user} = message,
        %EmailAccount{} = email_account,
        %{"email_message_id" => in_reply_to} = metadata,
        to_address
      ) do
    account = Accounts.get_account!(message.account_id)
    sender_name = Emails.format_sender_name(user, account)
    references = build_references(metadata["email_references"], in_reply_to)
    subject = build_subject(metadata["email_subject"], conversation_subject(message))
    message_id = generate_message_id(email_account.from_address)

    email =
      %{
        to: to_address,
        from: {sender_name, email_account.from_address},
        subject: subject,
        text: message.body,
        in_reply_to: in_reply_to,
        references: references,
        attachments: format_email_attachments(message.attachments)
      }
      |> Email.email_channel_reply()
      |> Swoosh.Email.header("Message-ID", message_id)

    case Mailers.deliver(email, smtp_config_for(email_account)) do
      {:ok, _receipt} ->
        {:ok, _message} =
          Messages.update_message(message, %{
            metadata:
              (message.metadata || %{})
              |> Map.merge(%{
                "email_message_id" => message_id,
                "email_in_reply_to" => in_reply_to,
                "email_references" => references,
                "email_subject" => subject,
                "email_from" => to_address,
                "email_account_id" => email_account.id
              })
          })

        :ok

      {:error, reason} = error ->
        Logger.error("[SendEmailAccountReply] Failed to send email: #{inspect(reason)}")

        error
    end
  end

  @doc """
  The active email account attached to the conversation's inbox, if any.
  """
  @spec find_email_account(Message.t()) :: EmailAccount.t() | nil
  def find_email_account(%Message{conversation: %Conversation{inbox_id: inbox_id}})
      when is_binary(inbox_id),
      do: EmailAccounts.find_by_inbox(inbox_id)

  def find_email_account(_message), do: nil

  @doc """
  The most recent (non-private) message in the conversation carrying
  `email_*` metadata — i.e. the message this reply threads onto. Mirrors the
  SES worker's previous-message lookup, but searches the whole conversation
  for the `email_message_id` key (and uses `<=` while excluding the message
  itself, so an inbound email processed in the same second is still found).
  """
  @spec get_previous_email_message(Message.t()) :: Message.t() | nil
  def get_previous_email_message(%Message{
        id: id,
        conversation_id: conversation_id,
        inserted_at: inserted_at
      }) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> where([m], m.id != ^id)
    |> where([m], m.inserted_at <= ^inserted_at)
    |> where([m], m.private == false)
    |> where([m], fragment("?->>'email_message_id' IS NOT NULL", m.metadata))
    |> order_by(desc: :inserted_at)
    |> first()
    |> Repo.one()
  end

  @doc """
  The address the reply should go to: the counterparty address recorded on
  the previous email message (mirrors how the SES worker replies to
  `ses_from`), falling back to the conversation customer's email address.
  """
  @spec recipient_address(map(), Conversation.t() | any()) :: String.t() | nil
  def recipient_address(%{"email_from" => email_from}, _conversation)
      when is_binary(email_from) and email_from != "",
      do: email_from

  def recipient_address(_metadata, %Conversation{customer_id: customer_id})
      when is_binary(customer_id) do
    case Customers.get_customer!(customer_id) do
      %Customer{email: email} when is_binary(email) and email != "" -> email
      _customer -> nil
    end
  end

  def recipient_address(_metadata, _conversation), do: nil

  @doc """
  Builds the per-delivery Swoosh SMTP config for an email account. Pure —
  exposed for testing.

  Mirrors `ChatApi.EmailAccounts.Client.smtp_opts/1` (same TLS mode mapping
  and the same secure-by-default TLS options, honoring
  `settings["allow_insecure_tls"]`), but in the shape expected by
  `Swoosh.Adapters.SMTP`.
  """
  @spec smtp_config_for(EmailAccount.t()) :: Keyword.t()
  def smtp_config_for(
        %EmailAccount{smtp_host: host, smtp_port: port, smtp_tls: tls} = email_account
      ) do
    [
      adapter: Swoosh.Adapters.SMTP,
      relay: host,
      port: port,
      # Connect to the configured host directly instead of resolving MX
      # records for its domain.
      no_mx_lookups: true,
      retries: 1
    ] ++ auth_config(email_account) ++ tls_config(tls, host, email_account.settings)
  end

  @doc """
  Generates a fresh RFC 5322 `Message-ID` scoped to the sending address's
  domain, e.g. `"<0f81b1e2-...-9d@company.com>"`.
  """
  @spec generate_message_id(String.t() | nil) :: String.t()
  def generate_message_id(from_address),
    do: "<#{UUID.uuid4()}@#{domain_of(from_address)}>"

  @doc """
  The domain part of an email address (used as the `Message-ID` host part).
  Falls back to `"localhost"` when the address has no domain.
  """
  @spec domain_of(String.t() | nil) :: String.t()
  def domain_of(address) when is_binary(address) do
    case String.split(address, "@", parts: 2) do
      [_local, domain] when domain != "" -> domain
      _other -> "localhost"
    end
  end

  def domain_of(_address), do: "localhost"

  @doc """
  Builds the `References` header for the outgoing reply: the previous
  message's references (if any) plus the message id being replied to.
  """
  @spec build_references(String.t() | nil, String.t()) :: String.t()
  def build_references(references, new_message_id) when references in [nil, ""],
    do: new_message_id

  def build_references(existing_references, new_message_id),
    do: existing_references <> " " <> new_message_id

  @doc """
  The subject for the outgoing reply: the previous email's subject (from the
  `email_subject` metadata), falling back to the conversation subject —
  prefixed with `"Re: "` unless it already carries one.
  """
  @spec build_subject(String.t() | nil, String.t() | nil) :: String.t()
  def build_subject(previous_subject, conversation_subject) do
    base = presence(previous_subject) || presence(conversation_subject) || ""

    cond do
      base == "" -> ""
      base =~ ~r/^re:/i -> base
      true -> "Re: " <> base
    end
  end

  @spec format_email_attachment(FileUpload.t() | any()) :: Swoosh.Attachment.t() | nil
  def format_email_attachment(%FileUpload{
        file_url: file_url,
        filename: filename,
        content_type: content_type
      }) do
    case ChatApi.Aws.download_file_url(file_url) do
      {:ok, %{body: data, status_code: 200}} ->
        Swoosh.Attachment.new({:data, data},
          content_type: content_type || "application/octet-stream",
          filename: filename,
          type: :attachment
        )

      _error ->
        nil
    end
  end

  def format_email_attachment(_attachment), do: nil

  @spec format_email_attachments(any()) :: [Swoosh.Attachment.t()]
  def format_email_attachments(attachments) when is_list(attachments),
    do: attachments |> Enum.map(&format_email_attachment/1) |> Enum.reject(&is_nil/1)

  def format_email_attachments(_attachments), do: []

  defp auth_config(%EmailAccount{} = email_account) do
    username = EmailAccounts.smtp_username(email_account)
    password = EmailAccounts.smtp_password(email_account)

    if blank?(username) or blank?(password) do
      # Swoosh's SMTP adapter requires string credentials whenever the keys
      # are present, so blank credentials are omitted entirely and we only
      # authenticate if the server offers it.
      [auth: :if_available]
    else
      [auth: :always, username: username, password: password]
    end
  end

  defp tls_config("ssl", host, settings),
    # gen_smtp only applies :tls_options on the STARTTLS upgrade path; an
    # implicit ssl connect takes its ssl options from :sockopts.
    do: [ssl: true, tls: :never, sockopts: Client.ssl_opts(host, settings)]

  defp tls_config("starttls", host, settings),
    do: [ssl: false, tls: :always, tls_options: Client.ssl_opts(host, settings)]

  defp tls_config(_none, _host, _settings), do: [ssl: false, tls: :never]

  defp conversation_subject(%Message{conversation: %Conversation{subject: subject}}),
    do: subject

  defp conversation_subject(_message), do: nil

  defp blank?(value), do: value in [nil, ""]

  defp presence(value), do: if(blank?(value), do: nil, else: value)
end
