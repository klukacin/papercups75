defmodule ChatApi.Accounts.AccountUser do
  @moduledoc """
  Join schema for user <-> account membership.

  Phase A (additive) of multi-account support: a user can be a member of many
  accounts. The legacy `users.account_id` remains the user's primary account and
  is kept in sync; this table is the source of truth for membership.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ChatApi.Accounts.Account
  alias ChatApi.Users.User

  @type t :: %__MODULE__{
          role: String.t(),
          account_id: binary(),
          account: any(),
          user_id: integer(),
          user: any(),
          inserted_at: any(),
          updated_at: any()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "account_users" do
    field(:role, :string, default: "user")

    belongs_to(:account, Account)
    belongs_to(:user, User, type: :integer)

    timestamps()
  end

  @doc false
  def changeset(account_user, attrs) do
    account_user
    |> cast(attrs, [:role, :account_id, :user_id])
    |> validate_required([:role, :account_id, :user_id])
    |> validate_inclusion(:role, ~w(admin user))
    |> unique_constraint([:account_id, :user_id],
      name: :account_users_account_id_user_id_index
    )
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:user_id)
  end
end
