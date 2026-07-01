defmodule ChatApi.Accounts.MembershipTest do
  use ChatApi.DataCase, async: true
  import ChatApi.Factory

  alias ChatApi.{Accounts, Users}

  describe "user_member_of?/2" do
    test "is true for a member and false otherwise" do
      account = insert(:account)
      other = insert(:account)
      user = insert(:user, account: account)
      insert(:account_user, user: user, account: account)

      assert Accounts.user_member_of?(user, account.id)
      refute Accounts.user_member_of?(user, other.id)
    end
  end

  describe "list_accounts_for_user/1" do
    test "returns every account the user is a member of" do
      user = insert(:user)
      account1 = insert(:account)
      account2 = insert(:account)
      insert(:account_user, user: user, account: account1)
      insert(:account_user, user: user, account: account2)

      ids = user |> Accounts.list_accounts_for_user() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([account1.id, account2.id])
    end
  end

  describe "create_account_user/3" do
    test "is idempotent on (account_id, user_id)" do
      account = insert(:account)
      user = insert(:user, account: account)

      assert {:ok, _} = Accounts.create_account_user(account.id, user.id, "admin")
      # Second insert is a no-op (on_conflict: :nothing), not an error.
      assert {:ok, _} = Accounts.create_account_user(account.id, user.id, "admin")
    end
  end

  describe "Users.create_user/1 membership mirroring" do
    test "automatically records membership for the primary account" do
      account = insert(:account)

      {:ok, user} =
        Users.create_user(%{
          email: "member-#{System.unique_integer([:positive])}@example.com",
          password: "supersecret123",
          password_confirmation: "supersecret123",
          account_id: account.id
        })

      assert Accounts.user_member_of?(user, account.id)
    end
  end
end
