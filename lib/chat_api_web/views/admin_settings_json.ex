defmodule ChatApiWeb.AdminSettingsJSON do
  # Both GET and PUT render the full, fresh settings state. The context
  # already shapes the entries (editable: key/type/value/source; env_only:
  # key/is_set/preview — previews are masked, never full secrets).
  def index(%{editable: editable, env_only: env_only}) do
    %{data: %{editable: editable, env_only: env_only}}
  end
end
