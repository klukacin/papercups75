defmodule ChatApi.Encryption do
  @moduledoc """
  Application-level encryption at rest (AES-256-GCM) for sensitive columns,
  used by `ChatApi.Ecto.EncryptedString`.

  ## Key

  The key comes from the `PAPERCUPS_ENCRYPTION_KEY` environment variable —
  32 random bytes, base64-encoded (generate one with
  `openssl rand -base64 32`) — and is read at runtime on every use, so it
  works with runtime-configured releases. Tests (or exotic deployments) can
  override it via `Application.put_env(:chat_api, :encryption_key, value)`;
  an explicit `nil` there simulates an unset key.

  ## Ciphertext format

      "enc:v1:" <> Base64(iv <> tag <> ciphertext)

  with a fresh random 12-byte IV and a 16-byte GCM tag per encryption.

  ## Graceful degradation

    * **No key configured:** `encrypt/1` stores the plaintext unchanged (and
      logs a warning once per VM), and `decrypt!/1` passes plaintext values
      through — self-hosters who never set the key keep working.
    * **Key configured later:** plaintext rows written before the key existed
      still read fine (no `enc:v1:` prefix → passthrough); run
      `mix encrypt_email_credentials` to encrypt them in place.
    * **Encrypted value, no key:** raises `#{inspect(__MODULE__)}.MissingKeyError`
      — ciphertext is unreadable without the key, never silently returned.
    * **Encrypted value, wrong key (or corrupted):** raises
      `#{inspect(__MODULE__)}.DecryptionError`.
  """

  require Logger

  defmodule MissingKeyError do
    defexception [:message]
  end

  defmodule DecryptionError do
    defexception [:message]
  end

  @env_var "PAPERCUPS_ENCRYPTION_KEY"
  @prefix "enc:v1:"
  @cipher :aes_256_gcm
  @key_bytes 32
  @iv_bytes 12
  @tag_bytes 16
  # Bound to the ciphertext version so a future v2 cannot be replayed as v1
  @aad "papercups:enc:v1"

  @warned_key {__MODULE__, :warned_missing_key}

  @doc "The `#{@prefix}` marker that identifies encrypted values."
  @spec ciphertext_prefix() :: String.t()
  def ciphertext_prefix, do: @prefix

  @doc "Whether `value` is an encrypted (`#{@prefix}`-prefixed) string."
  @spec encrypted?(term()) :: boolean()
  def encrypted?(value), do: is_binary(value) and String.starts_with?(value, @prefix)

  @doc "Whether an encryption key is currently configured."
  @spec configured?() :: boolean()
  def configured?, do: fetch_key() != :error

  @doc """
  Encrypts `plaintext` into the `#{@prefix}` format, or returns it unchanged
  (warning once per VM) when no key is configured. Raises `ArgumentError` for
  a malformed key.
  """
  @spec encrypt(binary()) :: binary()
  def encrypt(plaintext) when is_binary(plaintext) do
    case fetch_key() do
      {:ok, key} ->
        iv = :crypto.strong_rand_bytes(@iv_bytes)
        {ciphertext, tag} = :crypto.crypto_one_time_aead(@cipher, key, iv, plaintext, @aad, true)

        @prefix <> Base.encode64(iv <> tag <> ciphertext)

      :error ->
        warn_missing_key_once()
        plaintext
    end
  end

  @doc """
  Decrypts a `#{@prefix}`-prefixed value (raising `MissingKeyError` without a
  key and `DecryptionError` for a wrong key/corrupted ciphertext); any other
  binary is treated as legacy plaintext and returned unchanged.
  """
  @spec decrypt!(binary()) :: binary()
  def decrypt!(@prefix <> encoded = _value) do
    key =
      case fetch_key() do
        {:ok, key} ->
          key

        :error ->
          raise MissingKeyError,
                "found an encrypted (#{@prefix}) value but #{@env_var} is not set — " <>
                  "set it to the key the value was encrypted with; " <>
                  "encrypted credentials cannot be read without it"
      end

    with {:ok, <<iv::binary-size(@iv_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>>} <-
           Base.decode64(encoded),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(@cipher, key, iv, ciphertext, @aad, tag, false) do
      plaintext
    else
      _error ->
        raise DecryptionError,
              "could not decrypt value — wrong PAPERCUPS_ENCRYPTION_KEY or corrupted ciphertext"
    end
  end

  def decrypt!(plaintext) when is_binary(plaintext), do: plaintext

  @doc """
  Fetches the configured key as raw bytes. Returns `:error` when unset;
  raises `ArgumentError` when set but malformed (a misconfigured key must
  fail loudly rather than silently fall back to plaintext).
  """
  @spec fetch_key() :: {:ok, binary()} | :error
  def fetch_key do
    case raw_key() do
      value when value in [nil, ""] -> :error
      encoded -> {:ok, decode_key!(encoded)}
    end
  end

  # Test hook: makes the "warn once per VM" behavior assertable again.
  @doc false
  def reset_missing_key_warning, do: :persistent_term.erase(@warned_key)

  defp raw_key do
    case Application.fetch_env(:chat_api, :encryption_key) do
      {:ok, value} -> value
      :error -> System.get_env(@env_var)
    end
  end

  defp decode_key!(encoded) do
    case Base.decode64(String.trim(encoded)) do
      {:ok, <<key::binary-size(@key_bytes)>>} ->
        key

      _invalid ->
        raise ArgumentError,
              "#{@env_var} must be a base64-encoded 32-byte key " <>
                "(generate one with `openssl rand -base64 32`)"
    end
  end

  defp warn_missing_key_once do
    unless :persistent_term.get(@warned_key, false) do
      :persistent_term.put(@warned_key, true)

      Logger.warning(
        "[ChatApi.Encryption] #{@env_var} is not set — email account credentials are " <>
          "stored in plaintext. Generate a key with `openssl rand -base64 32`, set it, " <>
          "and run `mix encrypt_email_credentials` to encrypt existing rows."
      )
    end

    :ok
  end
end
