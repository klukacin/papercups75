defmodule ChatApi.EmailAccounts.EmailAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChatApi.Accounts.Account
  alias ChatApi.Inboxes.Inbox
  alias ChatApi.Users.User

  @tls_values ["ssl", "starttls", "none"]
  @statuses ["active", "disabled", "error"]

  @type t :: %__MODULE__{
          from_address: String.t(),
          imap_host: String.t(),
          imap_port: integer(),
          imap_tls: String.t(),
          imap_username: String.t(),
          imap_password: String.t(),
          imap_folder: String.t(),
          smtp_host: String.t(),
          smtp_port: integer(),
          smtp_tls: String.t(),
          smtp_username: String.t() | nil,
          smtp_password: String.t() | nil,
          status: String.t(),
          last_error: String.t() | nil,
          last_synced_at: DateTime.t() | nil,
          last_failed_at: DateTime.t() | nil,
          failure_count: integer(),
          settings: map(),
          metadata: map(),
          # Foreign keys
          account_id: Ecto.UUID.t(),
          inbox_id: Ecto.UUID.t(),
          user_id: integer() | nil,
          # Timestamps
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "email_accounts" do
    field(:from_address, :string)

    field(:imap_host, :string)
    field(:imap_port, :integer, default: 993)
    field(:imap_tls, :string, default: "ssl")
    field(:imap_username, :string)
    # Encrypted at rest (AES-256-GCM) when PAPERCUPS_ENCRYPTION_KEY is set;
    # application code always sees the plaintext.
    field(:imap_password, ChatApi.Ecto.EncryptedString)
    field(:imap_folder, :string, default: "INBOX")

    field(:smtp_host, :string)
    field(:smtp_port, :integer, default: 587)
    field(:smtp_tls, :string, default: "starttls")
    field(:smtp_username, :string)
    field(:smtp_password, ChatApi.Ecto.EncryptedString)

    field(:status, :string, default: "active")
    field(:last_error, :string)
    field(:last_synced_at, :utc_datetime)
    field(:last_failed_at, :utc_datetime)
    field(:failure_count, :integer, default: 0)
    field(:settings, :map, default: %{})
    field(:metadata, :map, default: %{})

    belongs_to(:account, Account)
    belongs_to(:inbox, Inbox)
    belongs_to(:user, User, type: :integer)

    timestamps()
  end

  def tls_values, do: @tls_values
  def statuses, do: @statuses

  @doc false
  def changeset(email_account, attrs) do
    email_account
    |> cast(drop_blank_passwords(attrs), [
      :from_address,
      :imap_host,
      :imap_port,
      :imap_tls,
      :imap_username,
      :imap_password,
      :imap_folder,
      :smtp_host,
      :smtp_port,
      :smtp_tls,
      :smtp_username,
      :smtp_password,
      :status,
      :last_error,
      :last_synced_at,
      :last_failed_at,
      :failure_count,
      :settings,
      :metadata,
      :account_id,
      :inbox_id,
      :user_id
    ])
    |> validate_required([
      :from_address,
      :imap_host,
      :imap_port,
      :imap_tls,
      :imap_username,
      :imap_password,
      :imap_folder,
      :smtp_host,
      :smtp_port,
      :smtp_tls,
      :account_id,
      :inbox_id
    ])
    |> validate_format(:from_address, ~r/^[^\s@]+@[^\s@]+$/,
      message: "must be a valid email address"
    )
    |> validate_inclusion(:imap_tls, @tls_values)
    |> validate_inclusion(:smtp_tls, @tls_values)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:imap_port,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 65_535
    )
    |> validate_number(:smtp_port,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 65_535
    )
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:inbox_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:inbox_id)
  end

  # Blank (nil or "") password params are dropped before casting so that
  # updates keep the stored password unless a new non-empty value is provided.
  # On create, `validate_required/2` still rejects a missing IMAP password.
  @password_fields [:imap_password, :smtp_password]

  defp drop_blank_passwords(attrs) do
    Enum.reduce(@password_fields, attrs, fn field, acc ->
      acc
      |> drop_blank(field)
      |> drop_blank(Atom.to_string(field))
    end)
  end

  defp drop_blank(attrs, key) do
    case attrs do
      %{^key => value} when value in [nil, ""] -> Map.delete(attrs, key)
      _ -> attrs
    end
  end
end
