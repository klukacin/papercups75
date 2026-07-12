defmodule ChatApi.InstanceSettings do
  @moduledoc """
  DB-backed instance settings that superadmins manage at runtime from the UI.

  Every editable setting shadows the environment variable of the same name and
  resolves as: **DB override -> env var -> nil** (callers layer their own
  hardcoded defaults on top, exactly as they did with `System.get_env/2`).
  Values are always persisted as strings; clearing a setting (nil or `""`)
  deletes its row so the env fallback takes over again.

  Only keys in the fixed whitelist below are editable. Boot-critical variables
  (database, secrets, mailer, storage...) intentionally stay env-only:
  `env_only_status/0` reports whether they are set, with a masked preview that
  never exposes the full value.
  """

  import Ecto.Query, warn: false

  alias ChatApi.InstanceSettings.Setting
  alias ChatApi.Repo

  # The editable whitelist: the REACT_APP_* set that `PageController` injects
  # into `window.__ENV__`, plus the two backend flags with runtime readers
  # (registration gate + invitation email toggle).
  @editable_settings [
    {"PAPERCUPS_REGISTRATION_DISABLED", :boolean},
    {"USER_INVITATION_EMAIL_ENABLED", :boolean},
    {"REACT_APP_FILE_UPLOADS_ENABLED", :boolean},
    {"REACT_APP_STORYTIME_ENABLED", :boolean},
    {"REACT_APP_EU_EDITION", :boolean},
    {"REACT_APP_DEBUG_MODE_ENABLED", :boolean},
    {"REACT_APP_URL", :string},
    {"REACT_APP_STRIPE_PUBLIC_KEY", :string},
    {"REACT_APP_SENTRY_DSN", :string},
    {"REACT_APP_LOGROCKET_ID", :string},
    {"REACT_APP_POSTHOG_TOKEN", :string},
    {"REACT_APP_POSTHOG_API_HOST", :string},
    {"REACT_APP_SLACK_CLIENT_ID", :string},
    {"REACT_APP_GITHUB_APP_NAME", :string},
    {"REACT_APP_ADMIN_ACCOUNT_ID", :string},
    {"REACT_APP_ADMIN_INBOX_ID", :string}
  ]

  @editable_keys Enum.map(@editable_settings, &elem(&1, 0))

  # Boot-critical/secret variables: visible (masked) in the admin UI but never
  # editable from the DB — the app can't even boot far enough to read a DB
  # override for most of these.
  @env_only_keys [
    "DATABASE_URL",
    "SECRET_KEY_BASE",
    "BACKEND_URL",
    "REDIS_URL",
    "REDIS_TLS_URL",
    "MAILER_ADAPTER",
    "AWS_ACCESS_KEY_ID",
    "AWS_REGION",
    "BUCKET_NAME",
    "PAPERCUPS_STRIPE_SECRET"
  ]

  # Longest prefix of a secret the masked preview may reveal.
  @preview_length 4

  @type source :: :override | :env
  @type editable_setting :: %{
          key: String.t(),
          type: :boolean | :string,
          value: String.t() | nil,
          source: String.t() | nil
        }
  @type env_only_entry :: %{key: String.t(), is_set: boolean(), preview: String.t() | nil}

  @spec editable_keys() :: [String.t()]
  def editable_keys(), do: @editable_keys

  @doc """
  Resolves a whitelisted key: DB override if a row exists, else the env var,
  else nil. Raises `ArgumentError` for keys outside the whitelist so typos in
  code paths fail loudly.
  """
  @spec get(String.t()) :: String.t() | nil
  def get(key) when key in @editable_keys do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> System.get_env(key)
    end
  end

  def get(key), do: raise(ArgumentError, "unknown instance setting: #{inspect(key)}")

  @doc """
  Boolean view of `get/1` with the same truthiness the env-var readers used:
  `"1"` and `"true"` are truthy, everything else (including unset) is falsy.
  """
  @spec enabled?(String.t()) :: boolean()
  def enabled?(key), do: get(key) in ["1", "true"]

  @doc """
  Upserts the DB override for a whitelisted key. `nil` or `""` deletes the row
  (restoring the env fallback); booleans are normalized to `"true"`/`"false"`.
  All values are stored as strings.
  """
  @spec set(String.t(), String.t() | boolean() | nil) ::
          {:ok, Setting.t() | nil}
          | {:error, :unknown_key | :invalid_value | Ecto.Changeset.t()}
  def set(key, value) when key in @editable_keys do
    case normalize_value(value) do
      {:ok, nil} ->
        Repo.delete_all(from(s in Setting, where: s.key == ^key))
        {:ok, nil}

      {:ok, string} ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: string})
        |> Repo.insert(
          on_conflict: {:replace, [:value, :updated_at]},
          conflict_target: :key
        )

      {:error, :invalid_value} = error ->
        error
    end
  end

  def set(_key, _value), do: {:error, :unknown_key}

  @doc """
  Applies a `%{"KEY" => value}` batch atomically. Every key must be
  whitelisted and every value a string, boolean or nil — otherwise nothing is
  applied and the offending keys are returned.
  """
  @spec update_settings(map()) ::
          :ok | {:error, {:unknown_keys, [String.t()]} | {:invalid_values, [String.t()]}}
  def update_settings(settings) when is_map(settings) do
    unknown_keys = settings |> Map.keys() |> Enum.reject(&(&1 in @editable_keys)) |> Enum.sort()

    invalid_values =
      settings
      |> Enum.reject(fn {_key, value} -> match?({:ok, _}, normalize_value(value)) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    cond do
      unknown_keys != [] ->
        {:error, {:unknown_keys, unknown_keys}}

      invalid_values != [] ->
        {:error, {:invalid_values, invalid_values}}

      true ->
        {:ok, _} = Repo.transaction(fn -> apply_settings!(settings) end)

        :ok
    end
  end

  @spec apply_settings!(map()) :: :ok
  defp apply_settings!(settings) do
    Enum.each(settings, fn {key, value} ->
      {:ok, _} = set(key, value)
    end)
  end

  @doc """
  The full whitelist with resolved values and their provenance:
  `source: "override"` when a DB row exists, `"env"` when the environment
  provides the value, `nil` when neither does. Loads all rows in ONE query.
  """
  @spec editable_settings() :: [editable_setting()]
  def editable_settings() do
    overrides = load_overrides()

    Enum.map(@editable_settings, fn {key, type} ->
      case resolve(key, overrides) do
        {:override, value} -> %{key: key, type: type, value: value, source: "override"}
        {:env, value} -> %{key: key, type: type, value: value, source: "env"}
        :unset -> %{key: key, type: type, value: nil, source: nil}
      end
    end)
  end

  @doc """
  Resolves the WHOLE whitelist (DB override -> env var -> nil) with a single
  DB query, returning `%{"KEY" => value | nil}`. Used by hot paths such as
  `PageController.server_env_data/0`, which runs on every page load.
  """
  @spec resolve_all() :: %{String.t() => String.t() | nil}
  def resolve_all() do
    overrides = load_overrides()

    Map.new(@editable_keys, fn key ->
      case resolve(key, overrides) do
        {_source, value} -> {key, value}
        :unset -> {key, nil}
      end
    end)
  end

  @doc """
  Read-only report on boot-critical env vars: whether each is set, plus a
  masked preview (at most the first #{@preview_length} characters and an
  ellipsis). The full value is NEVER included.
  """
  @spec env_only_status() :: [env_only_entry()]
  def env_only_status() do
    Enum.map(@env_only_keys, fn key ->
      case System.get_env(key) do
        nil -> %{key: key, is_set: false, preview: nil}
        value -> %{key: key, is_set: true, preview: mask(value)}
      end
    end)
  end

  @spec resolve(String.t(), map()) :: {:override | :env, String.t() | nil} | :unset
  defp resolve(key, overrides) do
    case Map.fetch(overrides, key) do
      {:ok, value} ->
        {:override, value}

      :error ->
        case System.get_env(key) do
          nil -> :unset
          value -> {:env, value}
        end
    end
  end

  @spec load_overrides() :: %{String.t() => String.t() | nil}
  defp load_overrides() do
    Setting
    |> where([s], s.key in ^@editable_keys)
    |> select([s], {s.key, s.value})
    |> Repo.all()
    |> Map.new()
  end

  @spec normalize_value(any()) :: {:ok, String.t() | nil} | {:error, :invalid_value}
  defp normalize_value(nil), do: {:ok, nil}
  defp normalize_value(""), do: {:ok, nil}
  defp normalize_value(true), do: {:ok, "true"}
  defp normalize_value(false), do: {:ok, "false"}
  defp normalize_value(value) when is_binary(value), do: {:ok, value}
  defp normalize_value(_value), do: {:error, :invalid_value}

  @spec mask(String.t()) :: String.t()
  defp mask(value), do: String.slice(value, 0, @preview_length) <> "…"
end
