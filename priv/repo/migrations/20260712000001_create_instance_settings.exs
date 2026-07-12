defmodule ChatApi.Repo.Migrations.CreateInstanceSettings do
  use Ecto.Migration

  @moduledoc """
  Key/value store for instance-level runtime settings managed by superadmins.

  A row is a DB *override* for the env var of the same name: readers resolve
  DB override -> env var -> default. Deleting a row restores the env fallback,
  so `value` never needs to be null in practice (clearing deletes the row).
  """

  def change do
    create table(:instance_settings, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:key, :string, null: false)
      add(:value, :text)

      timestamps()
    end

    create(unique_index(:instance_settings, [:key]))
  end
end
