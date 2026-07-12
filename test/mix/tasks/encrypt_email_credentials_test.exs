defmodule Mix.Tasks.EncryptEmailCredentialsTest do
  # async: false — toggles the process-global encryption key and Mix shell
  use ChatApi.DataCase, async: false

  import ChatApi.Factory

  alias ChatApi.EmailAccounts

  @key Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
      Application.delete_env(:chat_api, :encryption_key)
    end)

    account = insert(:account)
    inbox = insert(:inbox, account: account)

    # Inserted while no key is configured → stored as plaintext
    email_account =
      insert(:email_account,
        account: account,
        inbox: inbox,
        imap_password: "plaintext-imap",
        smtp_password: "plaintext-smtp"
      )

    {:ok, account: account, inbox: inbox, email_account: email_account}
  end

  defp run_task, do: Mix.Tasks.EncryptEmailCredentials.run([])

  defp put_key(key), do: Application.put_env(:chat_api, :encryption_key, key)

  defp raw_passwords(email_account_id) do
    %{rows: [[raw_imap, raw_smtp]]} =
      Repo.query!(
        "SELECT imap_password, smtp_password FROM email_accounts WHERE id = $1",
        [Ecto.UUID.dump!(email_account_id)]
      )

    {raw_imap, raw_smtp}
  end

  test "encrypts plaintext password columns", %{email_account: email_account} do
    assert {"plaintext-imap", "plaintext-smtp"} = raw_passwords(email_account.id)

    put_key(@key)
    run_task()

    {raw_imap, raw_smtp} = raw_passwords(email_account.id)
    assert String.starts_with?(raw_imap, "enc:v1:")
    assert String.starts_with?(raw_smtp, "enc:v1:")

    # The application still reads the same plaintext
    reloaded = EmailAccounts.get_email_account!(email_account.id)
    assert reloaded.imap_password == "plaintext-imap"
    assert reloaded.smtp_password == "plaintext-smtp"

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "1"
  end

  test "is idempotent: a second run leaves the ciphertext untouched", %{
    email_account: email_account
  } do
    put_key(@key)
    run_task()

    encrypted_once = raw_passwords(email_account.id)
    run_task()

    assert raw_passwords(email_account.id) == encrypted_once
  end

  test "encrypts only the still-plaintext columns of mixed rows", %{
    email_account: email_account
  } do
    put_key(@key)

    # Re-saving the SMTP password with the key configured encrypts it, while
    # the untouched IMAP column keeps its plaintext value
    {:ok, _updated} =
      EmailAccounts.update_email_account(email_account, %{smtp_password: "rotated-smtp"})

    {raw_imap, raw_smtp} = raw_passwords(email_account.id)
    assert raw_imap == "plaintext-imap"
    assert String.starts_with?(raw_smtp, "enc:v1:")

    run_task()

    {raw_imap_after, raw_smtp_after} = raw_passwords(email_account.id)
    assert String.starts_with?(raw_imap_after, "enc:v1:")
    # already-encrypted values are not rewritten
    assert raw_smtp_after == raw_smtp

    reloaded = EmailAccounts.get_email_account!(email_account.id)
    assert reloaded.imap_password == "plaintext-imap"
    assert reloaded.smtp_password == "rotated-smtp"
  end

  test "is a no-op when no encryption key is configured", %{email_account: email_account} do
    put_key(nil)
    run_task()

    assert {"plaintext-imap", "plaintext-smtp"} = raw_passwords(email_account.id)

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "PAPERCUPS_ENCRYPTION_KEY is not set"
  end
end
