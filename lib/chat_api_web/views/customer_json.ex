defmodule ChatApiWeb.CustomerJSON do
  import ChatApiWeb.JSONHelpers

  alias ChatApiWeb.{
    CompanyJSON,
    ConversationJSON,
    IssueJSON,
    MessageJSON,
    NoteJSON,
    TagJSON
  }

  alias ChatApi.Companies.Company
  alias ChatApi.Customers.Customer

  def index(%{page: page}) do
    %{
      data: Enum.map(page.entries, &customer/1),
      page_number: page.page_number,
      page_size: page.page_size,
      total_pages: page.total_pages,
      total_entries: page.total_entries
    }
  end

  def show(%{customer: customer}) do
    %{data: maybe(customer, &customer/1)}
  end

  def basic(customer) do
    %{
      id: customer.id,
      object: "customer",
      name: customer.name,
      email: customer.email,
      created_at: customer.inserted_at,
      updated_at: customer.updated_at,
      phone: customer.phone,
      external_id: customer.external_id,
      profile_photo_url: customer.profile_photo_url,
      company_id: customer.company_id,
      host: customer.host,
      pathname: customer.pathname,
      current_url: customer.current_url,
      browser: customer.browser,
      os: customer.os,
      metadata: customer.metadata,
      title: customer.name || customer.email || "Anonymous User"
    }
  end

  def customer(customer) do
    %{
      id: customer.id,
      object: "customer",
      name: customer.name,
      email: customer.email,
      created_at: customer.inserted_at,
      updated_at: customer.updated_at,
      first_seen: customer.first_seen,
      last_seen_at: customer.last_seen_at,
      phone: customer.phone,
      external_id: customer.external_id,
      profile_photo_url: customer.profile_photo_url,
      company_id: customer.company_id,
      host: customer.host,
      pathname: customer.pathname,
      current_url: customer.current_url,
      browser: customer.browser,
      os: customer.os,
      ip: customer.ip,
      metadata: customer.metadata,
      time_zone: customer.time_zone,
      title: customer.name || customer.email || "Anonymous User"
    }
    |> maybe_render_tags(customer)
    |> maybe_render_issues(customer)
    |> maybe_render_notes(customer)
    |> maybe_render_conversations(customer)
    |> maybe_render_messages(customer)
    |> maybe_render_company(customer)
  end

  defp maybe_render_tags(json, %Customer{tags: tags}) when is_list(tags),
    do: Map.merge(json, %{tags: Enum.map(tags, &TagJSON.tag/1)})

  defp maybe_render_tags(json, _), do: json

  defp maybe_render_issues(json, %Customer{issues: issues}) when is_list(issues),
    do: Map.merge(json, %{issues: Enum.map(issues, &IssueJSON.issue/1)})

  defp maybe_render_issues(json, _), do: json

  defp maybe_render_notes(json, %Customer{notes: notes}) when is_list(notes),
    do: Map.merge(json, %{notes: Enum.map(notes, &NoteJSON.note/1)})

  defp maybe_render_notes(json, _), do: json

  defp maybe_render_conversations(json, %Customer{conversations: conversations})
       when is_list(conversations) do
    Map.merge(json, %{conversations: Enum.map(conversations, &ConversationJSON.basic/1)})
  end

  defp maybe_render_conversations(json, _), do: json

  defp maybe_render_messages(json, %Customer{messages: messages}) when is_list(messages),
    do: Map.merge(json, %{messages: Enum.map(messages, &MessageJSON.message/1)})

  defp maybe_render_messages(json, _), do: json

  defp maybe_render_company(json, %Customer{company: company}) do
    case company do
      nil ->
        Map.merge(json, %{company: nil})

      %Company{} = company ->
        Map.merge(json, %{company: CompanyJSON.company(company)})

      _ ->
        json
    end
  end

  defp maybe_render_company(json, _), do: json
end
