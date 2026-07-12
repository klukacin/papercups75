defmodule ChatApi.Accounts.SuperadminTest do
  use ChatApi.DataCase, async: true
  import ChatApi.Factory

  alias ChatApi.{Accounts, Users}
  alias ChatApi.Users.User

  describe "superadmin?/1" do
    test "returns true for a superadmin (struct and id)" do
      user = insert(:user, is_superadmin: true)

      assert Accounts.superadmin?(user)
      assert Accounts.superadmin?(user.id)
    end

    test "returns false for a regular user (struct and id)" do
      user = insert(:user)

      refute Accounts.superadmin?(user)
      refute Accounts.superadmin?(user.id)
    end

    test "fails closed on nil and garbage input" do
      refute Accounts.superadmin?(nil)
      refute Accounts.superadmin?("not-a-user-id")
    end

    test "returns false for an unknown user id" do
      refute Accounts.superadmin?(-1)
    end

    test "reads the CURRENT database value, not a stale struct" do
      user = insert(:user)
      {:ok, _} = Users.set_superadmin(user, true)

      # The in-memory struct still says false, but the database says true.
      refute user.is_superadmin
      assert Accounts.superadmin?(user)
    end
  end

  describe "bootstrap_first_superadmin/0" do
    test "promotes the FIRST user on the instance (inserted_at ASC)" do
      first = insert(:user, inserted_at: ~N[2020-01-01 00:00:00])
      second = insert(:user, inserted_at: ~N[2020-01-02 00:00:00])

      assert Users.bootstrap_first_superadmin() == 1

      assert Accounts.superadmin?(first.id)
      refute Accounts.superadmin?(second.id)
    end

    test "breaks inserted_at ties by id ASC" do
      timestamp = ~N[2020-01-01 00:00:00]
      first = insert(:user, inserted_at: timestamp)
      second = insert(:user, inserted_at: timestamp)

      assert first.id < second.id
      assert Users.bootstrap_first_superadmin() == 1
      assert Accounts.superadmin?(first.id)
      refute Accounts.superadmin?(second.id)
    end

    test "is a no-op when there are no users" do
      assert Users.bootstrap_first_superadmin() == 0
    end

    test "is idempotent: a no-op when a superadmin already exists" do
      first = insert(:user, inserted_at: ~N[2020-01-01 00:00:00])
      existing = insert(:user, is_superadmin: true, inserted_at: ~N[2020-01-02 00:00:00])

      assert Users.bootstrap_first_superadmin() == 0

      # The existing superadmin keeps the flag; the first user is NOT promoted.
      assert Accounts.superadmin?(existing.id)
      refute Accounts.superadmin?(first.id)
    end
  end

  describe "set_superadmin/2" do
    test "grants and revokes the flag" do
      _other_superadmin = insert(:user, is_superadmin: true)
      user = insert(:user)

      assert {:ok, %User{is_superadmin: true}} = Users.set_superadmin(user, true)
      assert Accounts.superadmin?(user.id)

      assert {:ok, %User{is_superadmin: false}} = Users.set_superadmin(user, false)
      refute Accounts.superadmin?(user.id)
    end

    test "cannot revoke the LAST superadmin on the instance" do
      user = insert(:user, is_superadmin: true)

      assert {:error, :last_superadmin} = Users.set_superadmin(user, false)
      assert Accounts.superadmin?(user.id)
    end

    test "revoking a non-superadmin succeeds even when only one superadmin exists" do
      _last = insert(:user, is_superadmin: true)
      user = insert(:user)

      assert {:ok, %User{is_superadmin: false}} = Users.set_superadmin(user, false)
    end

    test "checks the database flag, not a stale struct, for the last-superadmin guard" do
      user = insert(:user)
      {:ok, _} = Users.set_superadmin(user, true)

      # `user` still says false in memory, but it IS the only superadmin.
      assert {:error, :last_superadmin} = Users.set_superadmin(user, false)
    end
  end

  describe "account_admin?/2 superadmin override" do
    test "a superadmin is treated as an admin of ANY account, without a membership row" do
      account = insert(:account)
      superadmin = insert(:user, is_superadmin: true)

      assert Accounts.account_admin?(superadmin.id, account.id)
      # ...but there is still no stored membership for them.
      refute Accounts.get_account_user(superadmin.id, account.id)
    end

    test "regular membership-role behavior is unchanged" do
      account = insert(:account)
      admin = insert(:user, account: account, role: "admin")
      member = insert(:user, account: account, role: "user")
      outsider = insert(:user)

      assert Accounts.account_admin?(admin.id, account.id)
      refute Accounts.account_admin?(member.id, account.id)
      refute Accounts.account_admin?(outsider.id, account.id)
    end
  end

  describe "count_account_admins/1" do
    test "counts admin memberships of the given account only" do
      account = insert(:account)
      other_account = insert(:account)

      insert(:user, account: account, role: "admin")
      insert(:user, account: account, role: "user")
      insert(:user, account: other_account, role: "admin")

      assert Accounts.count_account_admins(account.id) == 1
      assert Accounts.count_account_admins(other_account.id) == 1
    end
  end

  describe "is_superadmin is never castable from params" do
    test "Users.create_user/1 ignores an is_superadmin param" do
      account = insert(:account)

      {:ok, user} =
        Users.create_user(%{
          email: "sneaky-#{System.unique_integer([:positive])}@example.com",
          password: "supersecret123",
          password_confirmation: "supersecret123",
          account_id: account.id,
          is_superadmin: true
        })

      refute user.is_superadmin
      refute Accounts.superadmin?(user.id)
    end

    test "no public User changeset casts is_superadmin" do
      user = insert(:user)
      params = %{"is_superadmin" => true}

      changesets = [
        User.changeset(user, Map.put(params, "account_id", user.account_id)),
        User.role_changeset(user, Map.put(params, "role", "admin")),
        User.disabled_at_changeset(user, params),
        User.email_verification_changeset(user, params),
        User.password_reset_changeset(user, params),
        User.password_changeset(user, params)
      ]

      for changeset <- changesets do
        refute Map.has_key?(changeset.changes, :is_superadmin)
      end
    end
  end
end
