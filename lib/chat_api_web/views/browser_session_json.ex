defmodule ChatApiWeb.BrowserSessionJSON do
  import ChatApiWeb.JSONHelpers
  alias ChatApiWeb.{BrowserReplayEventJSON, CustomerJSON}

  def index(%{browser_sessions: browser_sessions}) do
    %{data: Enum.map(browser_sessions, &preview/1)}
  end

  def create(%{browser_session: browser_session}) do
    %{data: maybe(browser_session, &basic/1)}
  end

  def show(%{browser_session: browser_session}) do
    %{data: maybe(browser_session, &expanded/1)}
  end

  def basic(browser_session) do
    %{
      id: browser_session.id,
      object: "browser_session",
      account_id: browser_session.account_id,
      customer_id: browser_session.customer_id,
      metadata: browser_session.metadata,
      started_at: browser_session.started_at,
      finished_at: browser_session.finished_at
    }
  end

  def preview(browser_session) do
    %{
      id: browser_session.id,
      object: "browser_session",
      account_id: browser_session.account_id,
      customer_id: browser_session.customer_id,
      metadata: browser_session.metadata,
      started_at: browser_session.started_at,
      finished_at: browser_session.finished_at,
      customer: maybe(browser_session.customer, &CustomerJSON.basic/1)
    }
  end

  def expanded(browser_session) do
    %{
      id: browser_session.id,
      object: "browser_session",
      account_id: browser_session.account_id,
      customer_id: browser_session.customer_id,
      metadata: browser_session.metadata,
      started_at: browser_session.started_at,
      finished_at: browser_session.finished_at,
      customer: maybe(browser_session.customer, &CustomerJSON.basic/1),
      browser_replay_events:
        Enum.map(
          browser_session.browser_replay_events,
          &BrowserReplayEventJSON.browser_replay_event/1
        )
    }
  end
end
