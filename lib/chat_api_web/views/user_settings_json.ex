defmodule ChatApiWeb.UserSettingsJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{user_settings: user_settings}) do
    %{data: Enum.map(user_settings, &user_settings/1)}
  end

  def show(%{user_settings: user_settings}) do
    %{data: maybe(user_settings, &user_settings/1)}
  end

  def user_settings(user_settings) do
    %{
      id: user_settings.id,
      object: "user_settings",
      user_id: user_settings.user_id,
      email_alert_on_new_message: user_settings.email_alert_on_new_message,
      email_alert_on_new_conversation: user_settings.email_alert_on_new_conversation,
      expo_push_token: user_settings.expo_push_token
    }
  end
end
