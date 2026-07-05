defmodule ChatApiWeb.SlackAuthorizationJSON do
  import ChatApiWeb.JSONHelpers
  alias ChatApi.SlackAuthorizations

  def index(%{slack_authorizations: slack_authorizations}) do
    %{data: Enum.map(slack_authorizations, &slack_authorization/1)}
  end

  def show(%{slack_authorization: slack_authorization}) do
    %{data: maybe(slack_authorization, &slack_authorization/1)}
  end

  def slack_authorization(slack_authorization) do
    %{
      id: slack_authorization.id,
      object: "slack_authorization",
      account_id: slack_authorization.account_id,
      inbox_id: slack_authorization.inbox_id,
      channel: slack_authorization.channel,
      channel_id: slack_authorization.channel_id,
      configuration_url: slack_authorization.configuration_url,
      team_id: slack_authorization.team_id,
      team_name: slack_authorization.team_name,
      created_at: slack_authorization.inserted_at,
      updated_at: slack_authorization.updated_at,
      settings: settings(SlackAuthorizations.get_authorization_settings(slack_authorization))
    }
  end

  def settings(settings) do
    %{
      sync_all_incoming_threads: settings.sync_all_incoming_threads,
      sync_by_emoji_tagging: settings.sync_by_emoji_tagging,
      sync_trigger_emoji: settings.sync_trigger_emoji,
      forward_synced_messages_to_reply_channel: settings.forward_synced_messages_to_reply_channel
    }
  end
end
