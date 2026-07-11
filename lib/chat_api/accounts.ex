defmodule ChatApi.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias ChatApi.Repo

  alias ChatApi.Accounts.{Account, AccountUser, Settings, WorkingHours}
  alias ChatApi.Users.User

  @doc """
  Adds a user as a member of an account (Phase A multi-account membership).
  Idempotent: a repeated (account_id, user_id) is a no-op.
  """
  @spec create_account_user(binary(), integer(), String.t()) ::
          {:ok, AccountUser.t()} | {:error, Ecto.Changeset.t()}
  def create_account_user(account_id, user_id, role \\ "user") do
    %AccountUser{}
    |> AccountUser.changeset(%{
      account_id: account_id,
      user_id: user_id,
      role: role || "user"
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :user_id])
  end

  @doc """
  Backfills `account_users` membership rows for pre-existing users.

  Every `User` has exactly one primary account via `users.account_id`. Users
  created before Phase A (and any created outside `Users.create_user/1`) have no
  membership row, which would 403 them on their own data once
  `CurrentAccountPlug` is enforced. This ensures each user is a member of its
  primary account.

  Implementation notes / trade-offs:
    * Uses a single `INSERT ... SELECT` (`Repo.insert_all/3` from a source query)
      with a `NOT EXISTS` filter, so it is one round-trip regardless of table
      size (no N+1 per-user inserts).
    * Idempotent: the `NOT EXISTS` filter skips users that already have a
      membership, and `on_conflict: :nothing` on the unique
      `(account_id, user_id)` index guards against any race/duplicate.
    * Users with a nil `account_id` are skipped (the column is NOT NULL today, so
      this is purely defensive and never crashes).
    * Existing memberships are left untouched, preserving their `role`.

  Returns the number of membership rows created (for logging).
  """
  @spec backfill_account_memberships() :: non_neg_integer()
  def backfill_account_memberships do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    source =
      from(u in User,
        as: :user,
        where: not is_nil(u.account_id),
        where:
          not exists(
            from(au in AccountUser,
              where:
                au.account_id == parent_as(:user).account_id and
                  au.user_id == parent_as(:user).id
            )
          ),
        select: %{
          id: fragment("gen_random_uuid()"),
          account_id: u.account_id,
          user_id: u.id,
          role: fragment("COALESCE(?, 'user')", u.role),
          inserted_at: ^now,
          updated_at: ^now
        }
      )

    {count, _} =
      Repo.insert_all(AccountUser, source,
        on_conflict: :nothing,
        conflict_target: [:account_id, :user_id]
      )

    count
  end

  @doc "Returns true if the user is a member of the given account."
  @spec user_member_of?(User.t() | integer(), binary()) :: boolean()
  def user_member_of?(%User{id: user_id}, account_id), do: user_member_of?(user_id, account_id)

  def user_member_of?(user_id, account_id)
      when not is_nil(user_id) and is_binary(account_id) do
    AccountUser
    |> where(user_id: ^user_id, account_id: ^account_id)
    |> Repo.exists?()
  end

  # Fail closed for anything else (nil user, non-binary/malformed account id)
  # rather than letting a bad value reach an Ecto query (which would raise).
  def user_member_of?(_user_or_id, _account_id), do: false

  @doc "Lists all accounts a user is a member of."
  @spec list_accounts_for_user(User.t() | integer()) :: [Account.t()]
  def list_accounts_for_user(%User{id: user_id}), do: list_accounts_for_user(user_id)

  def list_accounts_for_user(user_id) when not is_nil(user_id) do
    Account
    |> join(:inner, [a], au in AccountUser, on: au.account_id == a.id)
    |> where([_a, au], au.user_id == ^user_id)
    |> select([a, _au], a)
    |> Repo.all()
  end

  @spec get_account_user(integer(), binary()) :: AccountUser.t() | nil
  def get_account_user(user_id, account_id) do
    Repo.get_by(AccountUser, user_id: user_id, account_id: account_id)
  end

  @doc """
  Returns true if the user is an ADMIN member of the given account, based on the
  `account_users` role (not the user's global `users.role`).
  """
  @spec account_admin?(integer(), binary()) :: boolean()
  def account_admin?(user_id, account_id) do
    case get_account_user(user_id, account_id) do
      %AccountUser{role: "admin"} -> true
      _ -> false
    end
  end

  @doc """
  Returns the resolved account id assigned by `ChatApiWeb.CurrentAccountPlug`.
  Raises if the plug was not applied to the conn.
  """
  @spec get_current_account_id!(Plug.Conn.t()) :: binary()
  def get_current_account_id!(%Plug.Conn{assigns: %{current_account_id: account_id}}),
    do: account_id

  def get_current_account_id!(%Plug.Conn{}) do
    raise "current_account_id not assigned: ChatApiWeb.CurrentAccountPlug must run before calling get_current_account_id!/1"
  end

  @doc """
  Non-raising account resolution for controllers. Returns the account id
  assigned by `ChatApiWeb.CurrentAccountPlug` (from the `x-account-id` header,
  membership-checked), falling back to the current user's primary account, and
  finally `nil` when neither is available. Safe to call from any action.
  """
  @spec get_current_account_id(Plug.Conn.t()) :: binary() | nil
  def get_current_account_id(%Plug.Conn{assigns: assigns}) do
    case assigns do
      %{current_account_id: account_id} when not is_nil(account_id) -> account_id
      %{current_user: %{account_id: account_id}} when not is_nil(account_id) -> account_id
      _ -> nil
    end
  end

  def get_current_account_id(%Plug.Conn{}), do: nil

  @spec list_accounts() :: [Account.t()]
  def list_accounts do
    Repo.all(Account)
  end

  @spec get_account!(binary()) :: Account.t()
  def get_account!(id) do
    Account
    |> join(:left, [a], u in assoc(a, :users), as: :users)
    |> join(:left, [a, users: u], p in assoc(u, :profile), as: :profile)
    |> where([_a, users: u], is_nil(u.archived_at))
    |> preload([_a, users: u, profile: p], [:widget_settings, users: {u, profile: p}])
    |> Repo.get!(id)
  end

  @spec create_account(map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def create_account(attrs \\ %{}) do
    Account.changeset(%Account{}, attrs)
    |> Repo.insert()
  end

  @spec update_account(Account.t(), map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def update_account(%Account{} = account, attrs) do
    account
    |> Account.changeset(attrs)
    |> Repo.update()
  end

  @spec update_billing_info(Account.t(), map()) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def update_billing_info(%Account{} = account, attrs) do
    account
    |> Account.billing_details_changeset(attrs)
    |> Repo.update()
  end

  @spec delete_account(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def delete_account(%Account{} = account) do
    Repo.delete(account)
  end

  @spec change_account(Account.t(), map()) :: Ecto.Changeset.t()
  def change_account(%Account{} = account, attrs \\ %{}) do
    Account.changeset(account, attrs)
  end

  @spec exists?(binary()) :: boolean()
  def exists?(id) do
    count =
      Account
      |> where(id: ^id)
      |> select([p], count(p.id))
      |> Repo.one()

    count > 0
  end

  @spec get_subscription_plan!(binary()) :: binary()
  def get_subscription_plan!(account_id) do
    Account
    |> where(id: ^account_id)
    |> select([:subscription_plan])
    |> Repo.one!()
    |> Map.get(:subscription_plan)
  end

  @spec get_account_settings!(binary()) :: Settings.t()
  def get_account_settings!(account_id) do
    Account
    |> where(id: ^account_id)
    |> select([:settings])
    |> Repo.one!()
    |> Map.get(:settings, %{})
  end

  @starter_plan_max_users 2
  @lite_plan_max_users 4

  @spec has_reached_user_capacity?(binary()) :: boolean()
  def has_reached_user_capacity?(account_id) do
    # NB: if you're self-hosting, you can run the following to upgrade your account:
    # ```
    # $ mix set_subscription_plan [YOUR_ACCOUNT_TOKEN] team
    # ```

    # Or, on Heroku:
    # ```
    # $ heroku run "mix set_subscription_plan [YOUR_ACCOUNT_TOKEN] team"
    # ```
    #
    # (These commands would update your account from the "starter" plan to the "team" plan.)
    case get_subscription_plan!(account_id) do
      "starter" -> count_active_users(account_id) >= @starter_plan_max_users
      "lite" -> count_active_users(account_id) >= @lite_plan_max_users
      "team" -> false
      _ -> false
    end
  end

  @spec count_active_users(binary()) :: integer()
  def count_active_users(account_id) do
    User
    |> where(account_id: ^account_id)
    |> where([u], is_nil(u.disabled_at) and is_nil(u.archived_at))
    |> select([p], count(p.id))
    |> Repo.one()
  end

  @spec get_primary_user(binary()) :: User.t()
  def get_primary_user(account_id) do
    User
    |> where(account_id: ^account_id, role: "admin")
    |> where([u], is_nil(u.disabled_at) and is_nil(u.archived_at))
    |> order_by(asc: :inserted_at)
    |> first()
    |> Repo.one()
  end

  @spec is_outside_working_hours?(Account.t(), DateTime.t()) :: boolean()
  def is_outside_working_hours?(%Account{working_hours: working_hours}, datetime)
      when is_list(working_hours) do
    minutes_since_midnight = ChatApi.Utils.DateTimeUtils.minutes_since_midnight(datetime)
    day_of_week = ChatApi.Utils.DateTimeUtils.day_of_week(datetime)

    working_hours
    |> Enum.find(fn wh ->
      wh
      |> WorkingHours.day_to_indexes()
      |> Enum.member?(day_of_week)
    end)
    |> case do
      %WorkingHours{start_minute: start_min, end_minute: end_min} ->
        minutes_since_midnight < start_min || minutes_since_midnight > end_min

      _ ->
        true
    end
  end

  def is_outside_working_hours?(_account, _datetime) do
    # For now, just return `false` if no valid working hours are set
    false
  end

  @spec is_outside_working_hours?(Account.t()) :: boolean()
  def is_outside_working_hours?(%Account{time_zone: time_zone} = account)
      when not is_nil(time_zone) do
    case DateTime.now(time_zone) do
      {:ok, datetime} ->
        is_outside_working_hours?(account, datetime)

      {:error, reason} ->
        Logger.error("Invalid time zone #{inspect(time_zone)} - #{inspect(reason)}")

        false
    end
  end

  def is_outside_working_hours?(_account) do
    # For now, if no time zone is found, just assume working hours are not
    # set and return `false`.
    # TODO: how should we handle accounts without a valid time zone?
    false
  end
end
