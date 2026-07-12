defmodule ChatApi.Repo.Migrations.AddIsSuperadminToUsers do
  use Ecto.Migration

  require Logger

  @moduledoc """
  Adds the instance-superadmin flag to users and bootstraps the FIRST user ever
  created on the instance (ORDER BY inserted_at ASC, id ASC) as a superadmin.

  Existing installations therefore keep an operator who can create workspaces,
  enter any workspace, and manage instance admins. On a fresh install there are
  no users yet, so the bootstrap is a no-op.
  """

  def up do
    alter table(:users) do
      add(:is_superadmin, :boolean, null: false, default: false)
    end

    # The bootstrap below reads the column added above, so force the DDL to
    # execute first.
    flush()

    count = ChatApi.Users.bootstrap_first_superadmin()

    Logger.info("[add_is_superadmin_to_users] bootstrapped #{count} instance superadmin(s)")
  end

  def down do
    alter table(:users) do
      remove(:is_superadmin)
    end
  end
end
