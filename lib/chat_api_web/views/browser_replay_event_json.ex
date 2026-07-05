defmodule ChatApiWeb.BrowserReplayEventJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{browser_replay_events: browser_replay_events}) do
    %{data: Enum.map(browser_replay_events, &browser_replay_event/1)}
  end

  def show(%{browser_replay_event: browser_replay_event}) do
    %{data: maybe(browser_replay_event, &browser_replay_event/1)}
  end

  def browser_replay_event(browser_replay_event) do
    %{
      id: browser_replay_event.id,
      object: "browser_replay_event",
      account_id: browser_replay_event.account_id,
      event: browser_replay_event.event,
      timestamp: browser_replay_event.timestamp
    }
  end
end
