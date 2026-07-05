defmodule ChatApiWeb.UserProfileJSON do
  import ChatApiWeb.JSONHelpers
  alias ChatApiWeb.UserJSON

  def show(%{user_profile: user_profile}) do
    %{data: maybe(user_profile, &UserJSON.user/1)}
  end
end
