defmodule ChatApi.Ecto.EncryptedString do
  @moduledoc """
  An `Ecto.Type` that transparently encrypts a string column at rest via
  `ChatApi.Encryption` (AES-256-GCM, `enc:v1:`-prefixed ciphertext).

  Application code only ever sees the plaintext: `cast/1` and struct fields
  hold the plaintext, `dump/1` encrypts on the way to the database and
  `load/1` decrypts on the way out.

  Semantics follow `ChatApi.Encryption`:

    * no `PAPERCUPS_ENCRYPTION_KEY` configured → values are stored and read
      as plaintext (with a one-time warning), so self-hosters without the
      key keep working;
    * stored plaintext values (from before the key existed) load unchanged
      even when the key is configured — enabling encryption later never
      breaks old rows (`mix encrypt_email_credentials` migrates them);
    * stored `enc:v1:` values *require* the key: loading without it (or with
      the wrong one) raises a clear error instead of returning garbage.
  """

  use Ecto.Type

  alias ChatApi.Encryption

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_other), do: :error

  @impl Ecto.Type
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_binary(value), do: {:ok, Encryption.encrypt(value)}
  def dump(_other), do: :error

  @impl Ecto.Type
  def load(nil), do: {:ok, nil}
  def load(value) when is_binary(value), do: {:ok, Encryption.decrypt!(value)}
  def load(_other), do: :error
end
