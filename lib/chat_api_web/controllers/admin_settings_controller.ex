defmodule ChatApiWeb.AdminSettingsController do
  use ChatApiWeb, :controller

  alias ChatApi.{Accounts, InstanceSettings}
  alias ChatApi.Users.User

  action_fallback(ChatApiWeb.FallbackController)

  @doc """
  Instance-level settings (`GET /api/admin/settings`): the editable whitelist
  (DB override -> env fallback, with provenance) plus a masked, read-only
  report on boot-critical env vars. Superadmin-only.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    with %User{} = current_user <- conn.assigns.current_user,
         :ok <- require_superadmin(current_user) do
      render_settings(conn)
    end
  end

  @doc """
  Applies a batch of overrides (`PUT /api/admin/settings` with
  `{"settings": {"KEY": "value" | true | false | null}}`). Booleans are stored
  as "true"/"false"; null (or "") clears the override so the env var applies
  again. All-or-nothing: an unknown key rejects the entire batch with a 422.
  Responds with the same payload as `index/2` (the fresh state).
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"settings" => settings}) when is_map(settings) do
    with %User{} = current_user <- conn.assigns.current_user,
         :ok <- require_superadmin(current_user),
         :ok <- apply_settings(settings) do
      render_settings(conn)
    end
  end

  def update(conn, params) do
    with %User{} = current_user <- conn.assigns.current_user,
         :ok <- require_superadmin(current_user) do
      {:error, :unprocessable_entity,
       "Expected a \"settings\" object, e.g. {\"settings\": {\"KEY\": \"value\"}}, " <>
         "got: #{inspect(Map.keys(params))}"}
    end
  end

  @spec render_settings(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_settings(conn) do
    render(conn, :index,
      editable: InstanceSettings.editable_settings(),
      env_only: InstanceSettings.env_only_status()
    )
  end

  @spec apply_settings(map()) :: :ok | {:error, :unprocessable_entity, String.t()}
  defp apply_settings(settings) do
    case InstanceSettings.update_settings(settings) do
      :ok ->
        :ok

      {:error, {:unknown_keys, keys}} ->
        {:error, :unprocessable_entity, "Unknown setting(s): #{Enum.join(keys, ", ")}"}

      {:error, {:invalid_values, keys}} ->
        {:error, :unprocessable_entity,
         "Invalid value(s) for setting(s) (expected string, boolean or null): " <>
           Enum.join(keys, ", ")}
    end
  end

  @spec require_superadmin(User.t()) :: :ok | {:error, :forbidden, String.t()}
  defp require_superadmin(%User{} = user) do
    if Accounts.superadmin?(user) do
      :ok
    else
      {:error, :forbidden, "Only instance admins can access this resource."}
    end
  end
end
