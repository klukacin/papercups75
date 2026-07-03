defmodule ChatApi.Repo.Migrations.CreateMentions do
  use Ecto.Migration

  def change do
    create table(:mentions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:seen_at, :utc_datetime)

      add(:account_id, references(:accounts, type: :uuid, on_delete: :delete_all))

      add(
        :conversation_id,
        references(:conversations, type: :uuid, on_delete: :delete_all)
      )

      add(:message_id, references(:messages, type: :uuid, on_delete: :delete_all))
      add(:user_id, references(:users, type: :integer))

      timestamps()
    end

    create index(:mentions, [:account_id])
    create index(:mentions, [:user_id])
    create index(:mentions, [:conversation_id])
    create index(:mentions, [:message_id])
  end
end
