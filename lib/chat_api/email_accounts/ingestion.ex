defmodule ChatApi.EmailAccounts.Ingestion do
  @moduledoc """
  Turns raw inbound IMAP messages into Papercups conversations/messages for
  the generic email channel.

  ## Pipeline (per raw message)

    1. **Size guard** → `{:ok, :skipped}`: raw messages larger than
       `settings["max_message_bytes"]` (default 10MB) are skipped without
       being parsed — the caller marks them seen so they are never
       re-downloaded.
    2. **Parse** via `ChatApi.EmailChannels.Mime.parse/1`. Anything
       unparseable (or without a usable `From` address) returns
       `{:error, :parse_failure}` — the caller still marks such messages
       seen so one poison message can never wedge the mailbox.
    3. **Loop/abuse guards** → `{:ok, :skipped}`: auto-generated /
       auto-replied (`Auto-Submitted`), bulk/junk (`Precedence`),
       autoresponder headers (`X-Autoreply`/`X-Autorespond`), or mail sent
       from the account's own address (bounce/self-loop).
    4. **Dedup** on the RFC `Message-ID` against previously stored
       `email_message_id` metadata, scoped to the workspace →
       `{:ok, :duplicate}`. This also makes reprocessing safe when a
       previous poll processed a message but failed to mark it seen. (The
       dedup and threading lookups are backed by partial expression indexes
       on `messages ((metadata->>'email_message_id'))` — see the
       `AddEmailMessageIdIndexesToMessages` migration.)
    5. **Sender resolution** (the Gmail rule): a `From` address matching a
       workspace user creates an *agent* message, anything else a
       *customer* message (`Customers.find_or_create_by_email/2`).
    6. **Thread resolution**, in order:
       1. any id in `References`/`In-Reply-To` matching a stored
          `email_message_id` in this workspace → that message's conversation;
       2. an open conversation on the same inbox with the same customer and
          the same normalized subject (leading `Re:`/`Fwd:` stripped);
       3. otherwise a new conversation (source `"email"`).
    7. **Create** the message with `email_*` metadata (so outbound replies
       via `ChatApi.Workers.SendEmailAccountReply` can thread onto it),
       attach files, and fire the shared notification chain — all through
       `ChatApi.EmailChannels`.
  """

  import Ecto.Query, warn: false

  require Logger

  alias ChatApi.{Customers, EmailChannels, Repo, Users}
  alias ChatApi.Conversations.Conversation
  alias ChatApi.Customers.Customer
  alias ChatApi.EmailAccounts.EmailAccount
  alias ChatApi.EmailChannels.Mime
  alias ChatApi.Messages.Message
  alias ChatApi.Users.User

  @subject_prefix_regex ~r/^(re|fwd?)\s*:\s*/i
  @auto_submitted_regex ~r/^\s*auto-(generated|replied)/i

  @type result ::
          {:ok, Message.t()} | {:ok, :skipped} | {:ok, :duplicate} | {:error, any()}

  @default_max_message_bytes 10 * 1024 * 1024

  @doc """
  Processes one raw RFC 2822 message fetched from the account's mailbox.

  Returns:

    * `{:ok, %Message{}}` — a message (and possibly conversation) was created
    * `{:ok, :skipped}` — auto-generated/bulk/self-addressed mail, or a
      message larger than `settings["max_message_bytes"]` (default 10MB)
    * `{:ok, :duplicate}` — the `Message-ID` was already ingested
    * `{:error, :parse_failure}` — poison message; safe to mark seen
    * `{:error, other}` — transient failure (e.g. database unavailable);
      the message should stay unseen and be retried on the next poll
  """
  @spec process_raw_email(binary(), EmailAccount.t()) :: result()
  def process_raw_email(raw, %EmailAccount{} = email_account) do
    max_bytes = max_message_bytes(email_account)

    if byte_size(raw) > max_bytes do
      # Terminal: the caller marks it seen, so an enormous newsletter or
      # attachment bomb can never be re-downloaded on every poll.
      Logger.warning(
        "[EmailAccounts.Ingestion] Skipping oversized inbound email for account " <>
          "#{email_account.id} (#{byte_size(raw)} bytes > #{max_bytes} byte limit)"
      )

      {:ok, :skipped}
    else
      parse_and_process(raw, email_account)
    end
  end

  defp parse_and_process(raw, %EmailAccount{} = email_account) do
    case Mime.parse(raw) do
      {:ok, email} ->
        process_email(email, email_account)

      {:error, reason} ->
        Logger.error(
          "[EmailAccounts.Ingestion] Could not parse inbound email for account " <>
            "#{email_account.id}: #{inspect(reason)}"
        )

        {:error, :parse_failure}
    end
  end

  # The raw-size cap: `settings["max_message_bytes"]`, defaulting to 10MB.
  # Invalid/non-positive values fall back to the default.
  defp max_message_bytes(%EmailAccount{settings: settings}) when is_map(settings) do
    case Map.get(settings, "max_message_bytes", Map.get(settings, :max_message_bytes)) do
      value when is_integer(value) and value > 0 -> value
      value when is_binary(value) -> parse_max_bytes(value)
      _missing_or_invalid -> @default_max_message_bytes
    end
  end

  defp max_message_bytes(_email_account), do: @default_max_message_bytes

  defp parse_max_bytes(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> @default_max_message_bytes
    end
  end

  @doc """
  Processes an already-parsed formatted email (see `ChatApi.EmailChannels.Mime`).
  """
  @spec process_email(Mime.formatted_email(), EmailAccount.t()) :: result()
  def process_email(email, %EmailAccount{} = email_account) do
    from_address = Mime.extract_email_address(email.from)

    cond do
      is_nil(from_address) ->
        Logger.error(
          "[EmailAccounts.Ingestion] Inbound email without a usable From address for " <>
            "account #{email_account.id} (message id #{inspect(email.message_id)})"
        )

        {:error, :parse_failure}

      auto_generated?(email) ->
        {:ok, :skipped}

      self_addressed?(from_address, email_account) ->
        {:ok, :skipped}

      duplicate?(email, email_account) ->
        {:ok, :duplicate}

      true ->
        create_email_message(email, from_address, email_account)
    end
  end

  @doc """
  Normalizes an email subject for the fallback threading rule: strips any
  leading `Re:`/`Fw:`/`Fwd:` prefixes (repeatedly, case-insensitively),
  trims whitespace and downcases — so `"Re: Help"` threads into `"Help"`.
  """
  @spec normalize_subject(String.t() | nil) :: String.t()
  def normalize_subject(nil), do: ""

  def normalize_subject(subject) when is_binary(subject),
    do: subject |> String.trim() |> strip_subject_prefixes() |> String.downcase()

  ## Creation

  defp create_email_message(email, from_address, %EmailAccount{} = email_account) do
    agent = Users.find_user_by_email(from_address, email_account.account_id)

    with {:ok, customer} <- resolve_customer(email, from_address, agent, email_account),
         {:ok, conversation_id} <- resolve_conversation(email, customer, email_account) do
      sender_params =
        case {agent, customer} do
          {%User{id: user_id}, _customer} -> %{user_id: user_id}
          {nil, %Customer{id: customer_id}} -> %{customer_id: customer_id}
        end

      sender_params
      |> Map.merge(%{
        body: email.formatted_text,
        account_id: email_account.account_id,
        conversation_id: conversation_id,
        source: "email",
        metadata: build_metadata(email, agent, customer, email_account),
        sent_at: message_sent_at(email)
      })
      |> EmailChannels.create_and_broadcast_message(email.attachments)
    else
      :skip ->
        Logger.info(
          "[EmailAccounts.Ingestion] Skipping agent email without a resolvable " <>
            "counterparty for account #{email_account.id} " <>
            "(message id #{inspect(email.message_id)})"
        )

        {:ok, :skipped}

      {:error, _reason} = error ->
        error
    end
  end

  # Customer resolution:
  #   * customer-sent mail → find/create the customer from the From address;
  #   * agent-sent mail (e.g. the agent CC'd the inbox on an outreach email)
  #     → the counterparty is the first recipient that isn't the account
  #     itself; there may legitimately be none (`{:ok, nil}`).
  defp resolve_customer(_email, from_address, nil = _agent, %EmailAccount{} = email_account),
    do: Customers.find_or_create_by_email(from_address, email_account.account_id)

  defp resolve_customer(email, _from_address, %User{}, %EmailAccount{} = email_account) do
    own_addresses = own_addresses(email_account)

    counterparty =
      (Mime.extract_email_addresses(email.to) ++ Mime.extract_email_addresses(email.cc))
      |> Enum.reject(fn address -> String.downcase(address) in own_addresses end)
      |> List.first()

    case counterparty do
      nil -> {:ok, nil}
      address -> Customers.find_or_create_by_email(address, email_account.account_id)
    end
  end

  ## Thread resolution

  defp resolve_conversation(email, customer, %EmailAccount{} = email_account) do
    conversation_id =
      find_conversation_id_by_references(email, email_account) ||
        find_conversation_id_by_subject(email, customer, email_account)

    case {conversation_id, customer} do
      {conversation_id, _customer} when is_binary(conversation_id) ->
        {:ok, conversation_id}

      {nil, %Customer{id: customer_id}} ->
        case EmailChannels.create_and_broadcast_conversation(%{
               account_id: email_account.account_id,
               inbox_id: email_account.inbox_id,
               customer_id: customer_id,
               subject: email.subject,
               source: "email"
             }) do
          {:ok, %Conversation{id: id}} -> {:ok, id}
          {:error, _reason} = error -> error
        end

      {nil, nil} ->
        # Agent-sent mail with no thread to join and no counterparty to open
        # a conversation with — nothing actionable.
        :skip
    end
  end

  defp find_conversation_id_by_references(email, %EmailAccount{account_id: account_id}) do
    case thread_reference_ids(email) do
      [] ->
        nil

      ids ->
        Message
        |> where(account_id: ^account_id)
        |> where([m], fragment("?->>'email_message_id'", m.metadata) in ^ids)
        |> order_by(desc: :inserted_at)
        |> limit(1)
        |> select([m], m.conversation_id)
        |> Repo.one()
    end
  end

  defp find_conversation_id_by_subject(_email, nil = _customer, _email_account), do: nil

  defp find_conversation_id_by_subject(
         %{subject: subject},
         %Customer{id: customer_id},
         %EmailAccount{
           account_id: account_id,
           inbox_id: inbox_id
         }
       ) do
    case normalize_subject(subject) do
      "" ->
        nil

      normalized ->
        Conversation
        |> where(account_id: ^account_id, customer_id: ^customer_id, status: "open")
        |> where(inbox_id: ^inbox_id)
        |> where([c], is_nil(c.archived_at))
        |> where([c], not is_nil(c.subject))
        |> order_by(desc: :inserted_at)
        |> Repo.all()
        |> Enum.find_value(fn %Conversation{id: id, subject: existing} ->
          if normalize_subject(existing) == normalized, do: id
        end)
    end
  end

  defp thread_reference_ids(email),
    do: Enum.uniq(List.wrap(email.in_reply_to) ++ email.references)

  ## Guards

  defp auto_generated?(%{headers: headers}) do
    auto_submitted = headers["auto-submitted"]
    precedence = headers["precedence"]

    cond do
      is_binary(auto_submitted) and auto_submitted =~ @auto_submitted_regex ->
        true

      is_binary(precedence) and String.downcase(String.trim(precedence)) in ["bulk", "junk"] ->
        true

      Map.has_key?(headers, "x-autoreply") ->
        true

      Map.has_key?(headers, "x-autorespond") ->
        true

      true ->
        false
    end
  end

  defp self_addressed?(from_address, %EmailAccount{} = email_account),
    do: String.downcase(from_address) in own_addresses(email_account)

  defp own_addresses(%EmailAccount{from_address: from_address, imap_username: imap_username}) do
    [from_address, imap_username]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
  end

  defp duplicate?(%{message_id: message_id}, %EmailAccount{account_id: account_id})
       when is_binary(message_id) do
    Message
    |> where(account_id: ^account_id)
    |> where([m], fragment("?->>'email_message_id' = ?", m.metadata, ^message_id))
    |> Repo.exists?()
  end

  defp duplicate?(_email, _email_account), do: false

  ## Metadata

  defp build_metadata(email, agent, customer, %EmailAccount{} = email_account) do
    metadata = Mime.format_message_metadata(email, email_account)

    case {agent, customer} do
      {%User{}, %Customer{email: customer_email}} when is_binary(customer_email) ->
        # For agent-authored inbound email the counterparty (the address the
        # outbound worker replies to via `email_from`) is the customer, not
        # the agent's own address.
        Map.put(metadata, "email_from", customer_email)

      _customer_sent_or_no_counterparty ->
        metadata
    end
  end

  defp message_sent_at(%{date: %DateTime{} = date}), do: DateTime.truncate(date, :second)
  defp message_sent_at(_email), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp strip_subject_prefixes(subject) do
    case Regex.replace(@subject_prefix_regex, subject, "", global: false) do
      ^subject -> subject
      stripped -> stripped |> String.trim() |> strip_subject_prefixes()
    end
  end
end
