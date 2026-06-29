defmodule ChatApi.Repo.Migrations.CreateAccountUsers do
  use Ecto.Migration

  def change do
    create table(:account_users, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:role, :string, null: false, default: "user")

      timestamps()
    end

    create(unique_index(:account_users, [:account_id, :user_id]))
    create(index(:account_users, [:user_id]))

    # Backfill membership from the existing 1:1 users.account_id relationship.
    execute(
      """
      INSERT INTO account_users (id, account_id, user_id, role, inserted_at, updated_at)
      SELECT gen_random_uuid(), u.account_id, u.id, COALESCE(u.role, 'user'), NOW(), NOW()
      FROM users u
      WHERE u.account_id IS NOT NULL
      ON CONFLICT (account_id, user_id) DO NOTHING;
      """,
      "DELETE FROM account_users;"
    )
  end
end
