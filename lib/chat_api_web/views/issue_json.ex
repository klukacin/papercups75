defmodule ChatApiWeb.IssueJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{issues: issues}) do
    %{data: Enum.map(issues, &issue/1)}
  end

  def show(%{issue: issue}) do
    %{data: maybe(issue, &issue/1)}
  end

  def issue(issue) do
    %{
      id: issue.id,
      object: "issue",
      created_at: issue.inserted_at,
      updated_at: issue.updated_at,
      title: issue.title,
      body: issue.body,
      state: issue.state,
      github_issue_url: issue.github_issue_url,
      closed_at: issue.closed_at,
      account_id: issue.account_id,
      creator_id: issue.creator_id,
      assignee_id: issue.assignee_id
    }
  end
end
