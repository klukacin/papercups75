defmodule Mix.Tasks.EncryptEmailCredentials do
  use Mix.Task

  import Ecto.Query, warn: false

  alias ChatApi.{EmailAccounts, Encryption, Repo}

  @shortdoc "Encrypts stored email account IMAP/SMTP passwords at rest"

  @moduledoc """
  Re-saves every `email_accounts` row whose IMAP/SMTP password is still
  stored in plaintext, so it becomes encrypted (AES-256-GCM, `enc:v1:`
  prefix) with the configured `PAPERCUPS_ENCRYPTION_KEY`.

    * **No-op without a key**: when `PAPERCUPS_ENCRYPTION_KEY` is not set,
      the task does nothing.
    * **Idempotent**: values that are already encrypted are left untouched,
      so the task can be re-run safely.

  Example:
  ```
  $ mix encrypt_email_credentials
  ```
  """

  @password_fields [:imap_password, :smtp_password]

  def run(_args) do
    Application.ensure_all_started(:chat_api)

    if Encryption.configured?() do
      rows = rows_needing_encryption()

      Enum.each(rows, &encrypt_row!/1)

      Mix.shell().info(
        "Encrypted the credentials of #{length(rows)} email account(s); " <>
          "already-encrypted rows were left untouched."
      )
    else
      Mix.shell().info(
        "PAPERCUPS_ENCRYPTION_KEY is not set — nothing to do. Generate a key with " <>
          "`openssl rand -base64 32` and re-run to encrypt stored email credentials."
      )
    end
  end

  # Reads the *raw* columns (bypassing the schema, whose load would decrypt)
  # to find rows with at least one plaintext password.
  defp rows_needing_encryption do
    from(ea in "email_accounts",
      select: %{
        id: type(ea.id, Ecto.UUID),
        imap_password: ea.imap_password,
        smtp_password: ea.smtp_password
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      {row.id, Enum.filter(@password_fields, fn field -> plaintext?(Map.fetch!(row, field)) end)}
    end)
    |> Enum.filter(fn {_id, plaintext_fields} -> plaintext_fields != [] end)
  end

  defp plaintext?(value),
    do: is_binary(value) and value != "" and not Encryption.encrypted?(value)

  # Force-writes only the still-plaintext fields; `EncryptedString.dump/1`
  # encrypts them on the way back to the database.
  defp encrypt_row!({id, plaintext_fields}) do
    email_account = EmailAccounts.get_email_account!(id)

    plaintext_fields
    |> Enum.reduce(Ecto.Changeset.change(email_account), fn field, changeset ->
      Ecto.Changeset.force_change(changeset, field, Map.fetch!(email_account, field))
    end)
    |> Repo.update!()
  end
end
