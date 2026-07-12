defmodule ChatApi.Messages.NotificationTest do
  use ChatApi.DataCase
  use Oban.Testing, repo: ChatApi.Repo

  import ChatApi.Factory

  alias ChatApi.Messages.{Message, Notification}
  alias ChatApi.Workers.SendEmailAccountReply

  setup do
    account = insert(:account)
    inbox = insert(:inbox, account: account)
    user = insert(:user, account: account)
    customer = insert(:customer, account: account)

    {:ok, account: account, inbox: inbox, user: user, customer: customer}
  end

  describe "notify/3 with :email_account" do
    test "enqueues a reply for agent messages in email conversations", ctx do
      conversation =
        insert(:conversation,
          account: ctx.account,
          inbox: ctx.inbox,
          customer: ctx.customer,
          source: "email"
        )

      message =
        insert(:message,
          account: ctx.account,
          conversation: conversation,
          user: ctx.user,
          customer: nil
        )

      assert %Message{} = Notification.notify(message, :email_account)

      assert_enqueued(
        worker: SendEmailAccountReply,
        args: %{"message_id" => message.id}
      )
    end

    test "does not enqueue for chat conversations", ctx do
      conversation =
        insert(:conversation,
          account: ctx.account,
          inbox: ctx.inbox,
          customer: ctx.customer,
          source: "chat"
        )

      message =
        insert(:message,
          account: ctx.account,
          conversation: conversation,
          user: ctx.user,
          customer: nil
        )

      assert %Message{} = Notification.notify(message, :email_account)
      refute_enqueued(worker: SendEmailAccountReply)
    end

    test "does not enqueue for customer (userless) messages", ctx do
      conversation =
        insert(:conversation,
          account: ctx.account,
          inbox: ctx.inbox,
          customer: ctx.customer,
          source: "email"
        )

      message =
        insert(:message,
          account: ctx.account,
          conversation: conversation,
          user: nil,
          customer: ctx.customer
        )

      assert %Message{} = Notification.notify(message, :email_account)
      refute_enqueued(worker: SendEmailAccountReply)
    end

    test "does not enqueue for private messages", ctx do
      conversation =
        insert(:conversation,
          account: ctx.account,
          inbox: ctx.inbox,
          customer: ctx.customer,
          source: "email"
        )

      message =
        insert(:message,
          account: ctx.account,
          conversation: conversation,
          user: ctx.user,
          customer: nil,
          private: true,
          type: "note"
        )

      assert %Message{} = Notification.notify(message, :email_account)
      refute_enqueued(worker: SendEmailAccountReply)
    end
  end
end
