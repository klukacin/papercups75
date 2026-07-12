defmodule ChatApi.Ecto.EncryptedStringTest do
  # async: false — these tests toggle the process-global encryption key
  use ChatApi.DataCase, async: false

  import ChatApi.Factory
  import ExUnit.CaptureLog

  alias ChatApi.Ecto.EncryptedString
  alias ChatApi.EmailAccounts
  alias ChatApi.Encryption

  @key Base.encode64(:crypto.strong_rand_bytes(32))
  @other_key Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    on_exit(fn -> Application.delete_env(:chat_api, :encryption_key) end)

    :ok
  end

  # `nil` simulates "no key configured" (overrides any ambient env var)
  defp put_key(key), do: Application.put_env(:chat_api, :encryption_key, key)

  describe "with an encryption key configured" do
    setup do
      put_key(@key)
      :ok
    end

    test "dump/load roundtrip: stores enc:v1: ciphertext, reads the plaintext back" do
      assert {:ok, ciphertext} = EncryptedString.dump("s3cret-password")

      assert String.starts_with?(ciphertext, "enc:v1:")
      refute ciphertext =~ "s3cret-password"

      # iv (12 bytes) <> tag (16 bytes) <> ciphertext, base64-encoded
      assert {:ok, decoded} =
               ciphertext |> String.replace_prefix("enc:v1:", "") |> Base.decode64()

      assert byte_size(decoded) == 12 + 16 + byte_size("s3cret-password")

      assert {:ok, "s3cret-password"} = EncryptedString.load(ciphertext)
    end

    test "every encryption uses a fresh IV (same plaintext, different ciphertext)" do
      assert {:ok, one} = EncryptedString.dump("same-secret")
      assert {:ok, two} = EncryptedString.dump("same-secret")

      assert one != two
      assert {:ok, "same-secret"} = EncryptedString.load(one)
      assert {:ok, "same-secret"} = EncryptedString.load(two)
    end

    test "loading a plaintext value passes it through unchanged (pre-key rows)" do
      assert {:ok, "legacy-plaintext"} = EncryptedString.load("legacy-plaintext")
    end

    test "nil dumps and loads as nil" do
      assert {:ok, nil} = EncryptedString.dump(nil)
      assert {:ok, nil} = EncryptedString.load(nil)
    end

    test "loading a value encrypted with a different key raises a clear error" do
      assert {:ok, ciphertext} = EncryptedString.dump("s3cret-password")

      put_key(@other_key)

      assert_raise Encryption.DecryptionError, ~r/wrong PAPERCUPS_ENCRYPTION_KEY/, fn ->
        EncryptedString.load(ciphertext)
      end
    end

    test "loading corrupted ciphertext raises a clear error" do
      assert_raise Encryption.DecryptionError, fn ->
        EncryptedString.load("enc:v1:not-even-base64!!!")
      end
    end

    test "a malformed key raises a clear error instead of storing plaintext" do
      put_key("definitely-not-32-base64-bytes")

      assert_raise ArgumentError, ~r/base64-encoded 32-byte key/, fn ->
        EncryptedString.dump("s3cret-password")
      end
    end
  end

  describe "without an encryption key" do
    setup do
      put_key(nil)
      :ok
    end

    test "dumps plaintext (graceful degradation) and warns exactly once" do
      Encryption.reset_missing_key_warning()

      first =
        capture_log(fn ->
          assert {:ok, "plain-password"} = EncryptedString.dump("plain-password")
        end)

      assert first =~ "PAPERCUPS_ENCRYPTION_KEY"

      second =
        capture_log(fn ->
          assert {:ok, "plain-password"} = EncryptedString.dump("plain-password")
        end)

      refute second =~ "PAPERCUPS_ENCRYPTION_KEY"
    end

    test "loads plaintext values as-is" do
      assert {:ok, "plain-password"} = EncryptedString.load("plain-password")
    end

    test "loading an enc:v1: value without the key raises a clear error" do
      put_key(@key)
      assert {:ok, ciphertext} = EncryptedString.dump("s3cret-password")

      put_key(nil)

      assert_raise Encryption.MissingKeyError, ~r/PAPERCUPS_ENCRYPTION_KEY/, fn ->
        EncryptedString.load(ciphertext)
      end
    end
  end

  describe "applied to the EmailAccount password fields" do
    test "the raw DB columns hold ciphertext while the struct reads plaintext" do
      put_key(@key)

      account = insert(:account)
      inbox = insert(:inbox, account: account)

      email_account =
        insert(:email_account,
          account: account,
          inbox: inbox,
          imap_password: "imap-secret",
          smtp_password: "smtp-secret"
        )

      # Transparent to application code: the struct field is the plaintext
      reloaded = EmailAccounts.get_email_account!(email_account.id)
      assert reloaded.imap_password == "imap-secret"
      assert reloaded.smtp_password == "smtp-secret"

      # ...but what is actually stored is ciphertext
      {raw_imap, raw_smtp} = raw_passwords(email_account.id)
      assert String.starts_with?(raw_imap, "enc:v1:")
      assert String.starts_with?(raw_smtp, "enc:v1:")
      refute raw_imap =~ "imap-secret"
      refute raw_smtp =~ "smtp-secret"

      # The effective-credentials helpers keep working
      assert EmailAccounts.smtp_password(reloaded) == "smtp-secret"
    end

    test "the effective-creds SMTP fallback still works on encrypted rows" do
      put_key(@key)

      account = insert(:account)
      inbox = insert(:inbox, account: account)

      email_account =
        insert(:email_account,
          account: account,
          inbox: inbox,
          imap_password: "imap-secret",
          smtp_password: nil
        )

      reloaded = EmailAccounts.get_email_account!(email_account.id)
      assert EmailAccounts.smtp_password(reloaded) == "imap-secret"

      {raw_imap, raw_smtp} = raw_passwords(email_account.id)
      assert String.starts_with?(raw_imap, "enc:v1:")
      assert raw_smtp == nil
    end

    test "updates through the changeset re-encrypt replaced passwords" do
      put_key(@key)

      account = insert(:account)
      inbox = insert(:inbox, account: account)
      email_account = insert(:email_account, account: account, inbox: inbox)

      assert {:ok, updated} =
               EmailAccounts.update_email_account(email_account, %{
                 imap_password: "rotated-secret"
               })

      assert updated.imap_password == "rotated-secret"

      {raw_imap, _raw_smtp} = raw_passwords(email_account.id)
      assert String.starts_with?(raw_imap, "enc:v1:")
      refute raw_imap =~ "rotated-secret"
    end

    test "without a key the raw DB columns stay plaintext (self-hosters keep working)" do
      put_key(nil)

      account = insert(:account)
      inbox = insert(:inbox, account: account)

      email_account =
        insert(:email_account,
          account: account,
          inbox: inbox,
          imap_password: "imap-secret",
          smtp_password: "smtp-secret"
        )

      assert {"imap-secret", "smtp-secret"} = raw_passwords(email_account.id)

      reloaded = EmailAccounts.get_email_account!(email_account.id)
      assert reloaded.imap_password == "imap-secret"
    end
  end

  defp raw_passwords(email_account_id) do
    %{rows: [[raw_imap, raw_smtp]]} =
      Repo.query!(
        "SELECT imap_password, smtp_password FROM email_accounts WHERE id = $1",
        [Ecto.UUID.dump!(email_account_id)]
      )

    {raw_imap, raw_smtp}
  end
end
