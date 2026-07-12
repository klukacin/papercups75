defmodule ChatApi.Repo.Migrations.CreateEmailAccounts do
  use Ecto.Migration

  def change do
    create table(:email_accounts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:from_address, :string, null: false)

      add(:imap_host, :string, null: false)
      add(:imap_port, :integer, default: 993)
      add(:imap_tls, :string, default: "ssl")
      add(:imap_username, :string, null: false)
      add(:imap_password, :string, null: false)
      add(:imap_folder, :string, default: "INBOX")

      add(:smtp_host, :string, null: false)
      add(:smtp_port, :integer, default: 587)
      add(:smtp_tls, :string, default: "starttls")
      add(:smtp_username, :string)
      add(:smtp_password, :string)

      add(:status, :string, default: "active")
      add(:last_error, :text)
      add(:last_synced_at, :utc_datetime)
      add(:failure_count, :integer, default: 0)
      add(:settings, :map, default: %{})
      add(:metadata, :map, default: %{})

      add(:account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false)
      add(:inbox_id, references(:inboxes, type: :uuid, on_delete: :delete_all), null: false)
      add(:user_id, references(:users, type: :integer))

      timestamps()
    end

    create(index(:email_accounts, [:account_id]))
    create(unique_index(:email_accounts, [:inbox_id]))
  end
end
