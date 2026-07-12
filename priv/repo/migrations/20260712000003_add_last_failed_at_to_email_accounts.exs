defmodule ChatApi.Repo.Migrations.AddLastFailedAtToEmailAccounts do
  use Ecto.Migration

  def change do
    alter table(:email_accounts) do
      add(:last_failed_at, :utc_datetime)
    end
  end
end
