defmodule ChatApiWeb.PersonalApiKeyJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{personal_api_keys: personal_api_keys}) do
    %{data: Enum.map(personal_api_keys, &personal_api_key/1)}
  end

  def show(%{personal_api_key: personal_api_key}) do
    %{data: maybe(personal_api_key, &personal_api_key/1)}
  end

  def personal_api_key(personal_api_key) do
    %{
      id: personal_api_key.id,
      object: "personal_api_key",
      label: personal_api_key.label,
      value: personal_api_key.value,
      last_used_at: personal_api_key.last_used_at,
      account_id: personal_api_key.account_id,
      user_id: personal_api_key.user_id
    }
  end
end
