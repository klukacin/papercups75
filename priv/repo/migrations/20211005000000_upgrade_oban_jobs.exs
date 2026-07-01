defmodule ChatApi.Repo.Migrations.UpgradeObanJobs do
  use Ecto.Migration

  # Bring the Oban schema up to the latest version supported by the installed
  # Oban (adds columns such as `meta`, `cancelled_at`, the `oban_peers` table,
  # etc.). `Oban.Migrations.up/0` is idempotent and only applies missing steps.
  def up do
    Oban.Migrations.up()
  end

  # Roll back only the steps added on top of the original install (version 1).
  def down do
    Oban.Migrations.down(version: 1)
  end
end
