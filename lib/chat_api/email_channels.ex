defmodule ChatApi.EmailChannels do
  @moduledoc """
  Channel-neutral helpers for turning inbound email into Papercups
  conversations and messages.

  Extracted from `ChatApi.Workers.ProcessSesEvent` (which delegates here) so
  that every email-ish channel — SES forwarding and the generic per-inbox
  IMAP channel (`ChatApi.EmailAccounts.Ingestion`) — creates records and
  fires the exact same notification chain (admin broadcast, webhooks, push,
  Slack, Mattermost and the post-creation hooks that e.g. reopen closed
  conversations).
  """

  require Logger

  alias ChatApi.{Aws, Conversations, Files, Messages}
  alias ChatApi.Conversations.Conversation
  alias ChatApi.Messages.Message

  @spec create_and_broadcast_conversation(map()) :: {:ok, Conversation.t()} | {:error, any()}
  def create_and_broadcast_conversation(params) do
    case Conversations.create_conversation(params) do
      {:ok, conversation} ->
        conversation
        |> Conversations.Notification.broadcast_new_conversation_to_admin!()
        |> Conversations.Notification.notify(:webhooks, event: "conversation:created")

        {:ok, conversation}

      error ->
        error
    end
  end

  @spec create_and_broadcast_message(map(), list()) :: {:ok, Message.t()} | {:error, any()}
  def create_and_broadcast_message(params, attachments \\ []) do
    case Messages.create_message(params) do
      {:ok, message} ->
        process_email_attachments(attachments, message)

        message.id
        |> Messages.get_message!()
        |> Messages.Notification.broadcast_to_admin!()
        |> Messages.Notification.notify(:webhooks)
        |> Messages.Notification.notify(:push)
        |> Messages.Notification.notify(:slack)
        |> Messages.Notification.notify(:mattermost)
        # NB: for email threads, for now we want to reopen the conversation if it was closed
        |> Messages.Helpers.handle_post_creation_hooks()

        {:ok, message}

      error ->
        error
    end
  end

  @spec process_email_attachment(map(), Message.t()) :: {:ok, any()} | {:error, any()}
  def process_email_attachment(
        %{
          filename: filename,
          body: body,
          content_type: content_type
        },
        %Message{} = message
      ) do
    with identifier <- Aws.generate_unique_filename(filename),
         {:ok, %{status_code: 200}} <- Aws.upload_binary(body, identifier),
         file_url <- Aws.get_file_url(identifier),
         {:ok, file} <-
           Files.create_file(%{
             "filename" => filename,
             "unique_filename" => identifier,
             "file_url" => file_url,
             "content_type" => content_type,
             "account_id" => message.account_id
           }),
         {:ok, _} <- Messages.add_attachment(message, file) do
      {:ok, file}
    else
      error ->
        Logger.error("Failed to process attachment #{inspect(filename)}: #{inspect(error)}")

        error
    end
  end

  @spec process_email_attachments(any(), Message.t()) :: :ok
  def process_email_attachments(nil, _), do: :ok
  def process_email_attachments([], _), do: :ok

  def process_email_attachments([_ | _] = attachments, %Message{} = message),
    do: Enum.each(attachments, &safe_process_email_attachment(&1, message))

  def process_email_attachments(_, _), do: :ok

  # A failing attachment must never fail the message it belongs to — log it
  # and move on to the next one.
  defp safe_process_email_attachment(attachment, %Message{} = message) do
    process_email_attachment(attachment, message)
  rescue
    error ->
      Logger.error("Failed to process attachment for message #{message.id}: #{inspect(error)}")

      {:error, error}
  end
end
