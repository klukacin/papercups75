defmodule ChatApi.Repo.Migrations.BackfillAccountUsers do
  use Ecto.Migration

  @doc """
  Data migration: ensure every existing user has an `account_users` membership
  row for its primary account (`users.account_id`).

  Delegates to `ChatApi.Accounts.backfill_account_memberships/0`, which is
  idempotent (NOT EXISTS filter + `on_conflict: :nothing`), so re-running is
  safe.
  """
  def up do
    created = ChatApi.Accounts.backfill_account_memberships()

    IO.puts("[backfill_account_users] created #{created} account_users membership row(s)")
  end

  def down do
    # No-op: memberships mirror the still-present users.account_id, so there is
    # nothing to reverse. Rows are cleaned up by the create_account_users
    # migration's own rollback if the table itself is dropped.
    :ok
  end
end
