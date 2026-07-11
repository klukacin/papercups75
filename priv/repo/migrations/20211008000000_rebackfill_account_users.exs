defmodule ChatApi.Repo.Migrations.RebackfillAccountUsers do
  use Ecto.Migration

  require Logger

  @moduledoc """
  Re-runs the account_users membership backfill.

  Between the original backfill (20211007000000) and the registration fix that
  mirrors membership for Pow-created users, users who registered via
  POST /api/registration got no account_users row and were locked out (403) of
  every protected route by CurrentAccountPlug. The backfill is idempotent, so
  running it again heals those users without touching existing memberships.
  """

  def up do
    count = ChatApi.Accounts.backfill_account_memberships()

    Logger.info("[rebackfill_account_users] created #{count} account_users membership row(s)")
  end

  def down do
    :ok
  end
end
