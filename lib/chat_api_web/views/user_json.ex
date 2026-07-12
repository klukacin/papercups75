defmodule ChatApiWeb.UserJSON do
  import ChatApiWeb.JSONHelpers

  alias ChatApi.Users.UserProfile

  def index(%{users: users}) do
    %{data: Enum.map(users, &user/1)}
  end

  def show(%{user: user}) do
    %{data: maybe(user, &user/1)}
  end

  def user(user) do
    case user do
      %{profile: %UserProfile{} = profile} ->
        %{
          id: user.id,
          object: "user",
          email: user.email,
          created_at: user.inserted_at,
          disabled_at: user.disabled_at,
          archived_at: user.archived_at,
          full_name: profile.full_name,
          display_name: profile.display_name,
          profile_photo_url: profile.profile_photo_url,
          role: user.role,
          is_superadmin: user.is_superadmin
        }

      _ ->
        %{
          id: user.id,
          object: "user",
          email: user.email,
          created_at: user.inserted_at,
          disabled_at: user.disabled_at,
          archived_at: user.archived_at,
          role: user.role,
          is_superadmin: user.is_superadmin
        }
    end
  end
end
