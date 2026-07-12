defmodule ChatApi.EmailChannels.Mime do
  @moduledoc """
  Parses raw RFC 2822/MIME emails (as fetched over IMAP) into the
  "formatted email" shape the other email channels use, and formats the
  `email_*` message metadata for the generic email channel.

  This is a generalization of `ChatApi.Aws.format_ses_email/2` and
  `ChatApi.Aws.format_message_parts/2` (which remain intact for the SES
  channel): same `Mail.Parsers.RFC2822` parsing, but independent of any
  SES message id, tolerant of extra `Content-Type` parameters, and aware of
  attachments that only carry a filename (no explicit
  `Content-Disposition: attachment`).

  The formatted email is a plain map with:

    * `:headers` — the full (downcased-key) header map, for guard checks
    * `:message_id` / `:in_reply_to` — normalized `<...>` message ids
    * `:references` — a *list* of normalized `<...>` message ids
    * `:subject`, `:from`, `:to`, `:cc`, `:bcc`, `:date` — as parsed
    * `:text`, `:html`, `:formatted_text` (reply text with quoted history
      stripped) and `:attachments` (`%{filename, body, content_type}`)
  """

  alias ChatApi.EmailAccounts.EmailAccount

  @type formatted_email :: map()

  @message_id_regex ~r/<[^>\s]+>/

  @doc """
  Parses a raw email binary into a formatted email map.

  Any exception raised by the underlying parser (poison messages, truncated
  MIME, headers without a `:` separator, ...) is caught and returned as
  `{:error, reason}` so a single bad message can never crash the caller.
  """
  @spec parse(binary()) :: {:ok, formatted_email()} | {:error, any()}
  def parse(raw) when is_binary(raw) do
    case raw |> normalize_line_endings() |> Mail.Parsers.RFC2822.parse() do
      %Mail.Message{headers: headers} = message when is_map(headers) and map_size(headers) > 0 ->
        {:ok, format_email(message)}

      other ->
        {:error, {:invalid_mime, other}}
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  def parse(_raw), do: {:error, :invalid_mime}

  @doc """
  Formats a parsed `%Mail.Message{}` into the formatted email map described
  in the moduledoc.
  """
  @spec format_email(Mail.Message.t()) :: formatted_email()
  def format_email(%Mail.Message{body: body, headers: headers, parts: parts} = message) do
    %{
      headers: headers,
      message_id: normalize_message_id(headers["message-id"]),
      subject: headers["subject"],
      from: headers["from"],
      to: headers["to"],
      cc: headers["cc"],
      bcc: headers["bcc"],
      in_reply_to: normalize_message_id(headers["in-reply-to"]),
      references: reference_ids(headers["references"]),
      date: headers["date"],
      text: nil,
      html: nil,
      formatted_text: nil,
      attachments: []
    }
    |> put_top_level_body(message, body)
    |> format_message_parts(parts)
    |> Map.update!(:attachments, &Enum.reverse/1)
  end

  @doc """
  Folds (possibly nested) MIME parts into the formatted email: plain-text
  and HTML bodies plus decoded attachments. Generalized from
  `ChatApi.Aws.format_message_parts/2`.
  """
  @spec format_message_parts(formatted_email(), any()) :: formatted_email()
  def format_message_parts(email, parts) when is_list(parts),
    do: Enum.reduce(parts, email, &format_message_part/2)

  def format_message_parts(email, _parts), do: email

  defp format_message_part(%Mail.Message{multipart: true, parts: embedded}, acc),
    do: format_message_parts(acc, embedded)

  defp format_message_part(%Mail.Message{body: body, headers: headers}, acc) do
    content_type = content_type(headers)

    cond do
      attachment?(headers, content_type) ->
        attachment = %{
          filename: attachment_filename(headers) || "attachment",
          body: body,
          content_type: content_type
        }

        %{acc | attachments: [attachment | acc.attachments]}

      content_type == "text/plain" and is_binary(body) ->
        %{acc | text: body, formatted_text: ChatApi.Google.Gmail.remove_original_email(body)}

      content_type == "text/html" and is_binary(body) ->
        %{acc | html: body}

      true ->
        acc
    end
  end

  defp format_message_part(_part, acc), do: acc

  # For single-part messages the body lives on the message itself; classify
  # it by the top-level content type (defaults to text/plain per RFC 2045).
  defp put_top_level_body(email, _message, nil), do: email

  defp put_top_level_body(email, %Mail.Message{multipart: true}, _body), do: email

  defp put_top_level_body(email, %Mail.Message{headers: headers}, body) when is_binary(body) do
    case content_type(headers) do
      "text/html" ->
        %{email | html: body}

      _text_or_unknown ->
        %{email | text: body, formatted_text: ChatApi.Google.Gmail.remove_original_email(body)}
    end
  end

  defp put_top_level_body(email, _message, _body), do: email

  @doc """
  Formats the `email_*` metadata persisted on inbound email messages —
  the same namespace `ChatApi.Workers.SendEmailAccountReply` writes for
  outbound replies, so threading works in both directions.

  `email_references` is stored as a space-separated string (the shape the
  outbound worker appends to when building its own `References` header);
  `email_from` is the counterparty address replies should go back to.
  """
  @spec format_message_metadata(formatted_email(), EmailAccount.t()) :: map()
  def format_message_metadata(email, %EmailAccount{id: email_account_id}) do
    %{
      "email_message_id" => email.message_id,
      "email_in_reply_to" => email.in_reply_to,
      "email_references" => join_references(email.references),
      "email_subject" => email.subject,
      "email_from" => extract_email_address(email.from),
      "email_to" => extract_email_addresses(email.to),
      "email_account_id" => email_account_id
    }
    |> maybe_put_raw_html(email)
  end

  # Mirrors `ChatApi.Aws.maybe_merge_raw_html/2`: when there is no plain-text
  # body to render, keep the raw HTML around in the metadata.
  defp maybe_put_raw_html(metadata, %{formatted_text: formatted_text, html: html})
       when formatted_text in [nil, ""] and is_binary(html),
       do: Map.put(metadata, "email_html", html)

  defp maybe_put_raw_html(metadata, _email), do: metadata

  @doc """
  Extracts the bare email address from a parsed address header value
  (`{name, address}` tuples, plain strings — possibly still in
  `"Name <address>"` form — or lists thereof, in which case the first entry
  wins).
  """
  @spec extract_email_address(any()) :: String.t() | nil
  def extract_email_address({_name, address}) when is_binary(address),
    do: extract_email_address(address)

  def extract_email_address([first | _rest]), do: extract_email_address(first)

  def extract_email_address(address) when is_binary(address) do
    case Regex.run(~r/<([^>\s]+)>/, address) do
      [_full, bare] -> presence(bare)
      _no_brackets -> presence(String.trim(address))
    end
  end

  def extract_email_address(_other), do: nil

  @doc """
  Extracts all bare email addresses from a parsed address header value.
  """
  @spec extract_email_addresses(any()) :: [String.t()]
  def extract_email_addresses(value) when is_list(value) do
    value
    |> Enum.map(&extract_email_address/1)
    |> Enum.reject(&is_nil/1)
  end

  def extract_email_addresses(nil), do: []
  def extract_email_addresses(value), do: extract_email_addresses([value])

  @doc """
  Normalizes a `Message-ID`-style header value to its canonical `<...>`
  form (or a trimmed bare id when the brackets are missing).
  """
  @spec normalize_message_id(any()) :: String.t() | nil
  def normalize_message_id(value) when is_binary(value) do
    case Regex.run(@message_id_regex, value) do
      [id] -> id
      _no_match -> presence(String.trim(value))
    end
  end

  def normalize_message_id(_value), do: nil

  @doc """
  Extracts the list of message ids from a `References`/`In-Reply-To`-style
  header value.
  """
  @spec reference_ids(any()) :: [String.t()]
  def reference_ids(value) when is_binary(value) do
    case Regex.scan(@message_id_regex, value) do
      [] -> value |> String.trim() |> presence() |> List.wrap()
      matches -> matches |> List.flatten() |> Enum.uniq()
    end
  end

  def reference_ids(_value), do: []

  defp join_references([]), do: nil
  defp join_references(references) when is_list(references), do: Enum.join(references, " ")

  # `Mail.Parsers.RFC2822` splits strictly on CRLF; make LF-only input
  # (fixtures, mailboxes rewritten by intermediate tooling) parseable too.
  defp normalize_line_endings(raw) do
    if String.contains?(raw, "\r\n") do
      raw
    else
      String.replace(raw, "\n", "\r\n")
    end
  end

  defp content_type(headers) do
    case headers["content-type"] do
      [type | _params] when is_binary(type) -> String.downcase(type)
      type when is_binary(type) -> String.downcase(type)
      _missing -> "text/plain"
    end
  end

  defp disposition(headers) do
    case headers["content-disposition"] do
      [disposition | _params] when is_binary(disposition) -> String.downcase(disposition)
      disposition when is_binary(disposition) -> String.downcase(disposition)
      _missing -> nil
    end
  end

  # A part is an attachment when it is explicitly marked as one, or when it
  # carries a filename and is not a renderable text body (covers inline
  # attachments as sent by e.g. Apple Mail).
  defp attachment?(headers, content_type) do
    case disposition(headers) do
      "attachment" ->
        true

      _other ->
        attachment_filename(headers) != nil and
          content_type not in ["text/plain", "text/html"]
    end
  end

  defp attachment_filename(headers) do
    header_param(headers["content-disposition"], "filename") ||
      header_param(headers["content-type"], "name")
  end

  defp header_param(value, param_name) when is_list(value) do
    Enum.find_value(value, fn
      {^param_name, param_value} -> presence(param_value)
      _other -> nil
    end)
  end

  defp header_param(_value, _param_name), do: nil

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
