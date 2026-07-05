defmodule ChatApiWeb.CannedResponseJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{canned_responses: canned_responses}) do
    %{data: Enum.map(canned_responses, &canned_response/1)}
  end

  def show(%{canned_response: canned_response}) do
    %{data: maybe(canned_response, &canned_response/1)}
  end

  def canned_response(canned_response) do
    %{id: canned_response.id, name: canned_response.name, content: canned_response.content}
  end
end
