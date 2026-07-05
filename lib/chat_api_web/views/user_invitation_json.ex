defmodule ChatApiWeb.UserInvitationJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{user_invitations: user_invitations}) do
    %{data: Enum.map(user_invitations, &user_invitation/1)}
  end

  def show(%{user_invitation: user_invitation}) do
    %{data: maybe(user_invitation, &user_invitation/1)}
  end

  def user_invitation(user_invitation) do
    %{
      id: user_invitation.id,
      account_id: user_invitation.account_id,
      expires_at: user_invitation.expires_at
    }
  end
end
