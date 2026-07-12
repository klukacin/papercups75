defmodule ChatApi.Repo.Migrations.AddEmailMessageIdIndexesToMessages do
  use Ecto.Migration

  @moduledoc """
  Partial expression indexes backing the email channel's Message-ID dedup and
  threading lookups (`ChatApi.EmailAccounts.Ingestion`), which query:

      WHERE account_id = $1 AND metadata->>'email_message_id' = $2
      WHERE account_id = $1 AND metadata->>'email_message_id' = ANY($2)

  The composite `(account_id, (metadata->>'email_message_id'))` index matches
  those queries exactly; the bare expression index additionally covers any
  cross-account lookup on the Message-ID. Both are partial on
  `metadata->>'email_message_id' IS NOT NULL` so the (vast) majority of
  non-email messages never enter the index — Postgres can still use them
  because `expr = const` is a strict operator and implies `expr IS NOT NULL`.
  """

  def change do
    create(
      index(:messages, ["(metadata->>'email_message_id')"],
        name: :messages_email_message_id_index,
        where: "metadata->>'email_message_id' IS NOT NULL"
      )
    )

    create(
      index(:messages, [:account_id, "(metadata->>'email_message_id')"],
        name: :messages_account_id_email_message_id_index,
        where: "metadata->>'email_message_id' IS NOT NULL"
      )
    )
  end
end
