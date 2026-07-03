defmodule ChatApi.Accounts.BackfillMembershipsTest do
  use ChatApi.DataCase, async: true
  import ChatApi.Factory

  alias ChatApi.Accounts
  alias ChatApi.Accounts.AccountUser
  alias ChatApi.Repo

  # NB: `insert(:user, ...)` goes straight through the factory/Repo and does NOT
  # run `Users.create_user/1`, so it never mirrors a membership row. That makes a
  # factory-inserted user a faithful stand-in for a pre-Phase-A "legacy" user.

  describe "backfill_account_memberships/0" do
    test "creates a membership for a legacy user that has none" do
      account = insert(:account)
      user = insert(:user, account: account)

      refute Accounts.user_member_of?(user, account.id)

      assert Accounts.backfill_account_memberships() >= 1
      assert Accounts.user_member_of?(user, account.id)
    end

    test "running twice does not create duplicates and does not crash" do
      account = insert(:account)
      user = insert(:user, account: account)

      assert Accounts.backfill_account_memberships() >= 1
      count_after_first = Repo.aggregate(AccountUser, :count)

      # Second run is a safe no-op (no unique-constraint crash, no new rows).
      assert Accounts.backfill_account_memberships() == 0
      assert Repo.aggregate(AccountUser, :count) == count_after_first

      # Exactly one membership row for this user/account.
      assert Repo.aggregate(
               from(au in AccountUser, where: au.user_id == ^user.id),
               :count
             ) == 1
    end

    test "second run returns 0 created (idempotent)" do
      account = insert(:account)
      insert(:user, account: account)

      assert Accounts.backfill_account_memberships() >= 1
      assert Accounts.backfill_account_memberships() == 0
    end

    test "leaves an existing membership untouched and preserves its role" do
      account = insert(:account)
      user = insert(:user, account: account)
      existing = insert(:account_user, user: user, account: account, role: "admin")

      created = Accounts.backfill_account_memberships()
      assert created == 0

      reloaded = Repo.get!(AccountUser, existing.id)
      assert reloaded.role == "admin"

      assert Repo.aggregate(
               from(au in AccountUser, where: au.user_id == ^user.id),
               :count
             ) == 1
    end

    test "backfills a legacy user while skipping one that already has membership" do
      # Legacy user (no membership)
      account1 = insert(:account)
      legacy = insert(:user, account: account1)

      # Already-a-member user
      account2 = insert(:account)
      member = insert(:user, account: account2)
      insert(:account_user, user: member, account: account2, role: "admin")

      # Only the legacy user should get a new row.
      assert Accounts.backfill_account_memberships() == 1

      assert Accounts.user_member_of?(legacy, account1.id)
      assert Accounts.user_member_of?(member, account2.id)
      assert Repo.get_by(AccountUser, user_id: member.id).role == "admin"
    end

    test "preserves the user's role on the backfilled membership" do
      account = insert(:account)
      user = insert(:user, account: account, role: "admin")

      assert Accounts.backfill_account_memberships() >= 1

      membership = Repo.get_by(AccountUser, user_id: user.id, account_id: account.id)
      assert membership.role == "admin"
    end
  end
end
