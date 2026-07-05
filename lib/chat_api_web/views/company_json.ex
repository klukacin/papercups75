defmodule ChatApiWeb.CompanyJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{companies: companies}) do
    %{data: Enum.map(companies, &company/1)}
  end

  def show(%{company: company}) do
    %{data: maybe(company, &company/1)}
  end

  def company(company) do
    %{
      id: company.id,
      object: "company",
      name: company.name,
      created_at: company.inserted_at,
      updated_at: company.updated_at,
      account_id: company.account_id,
      external_id: company.external_id,
      website_url: company.website_url,
      description: company.description,
      logo_image_url: company.logo_image_url,
      industry: company.industry,
      slack_channel_id: company.slack_channel_id,
      slack_channel_name: company.slack_channel_name,
      slack_team_id: company.slack_team_id,
      slack_team_name: company.slack_team_name,
      metadata: company.metadata
    }
  end
end
