defmodule ChatApiWeb.AccountJSON do
  import ChatApiWeb.JSONHelpers

  alias ChatApi.{Utils, Accounts}

  alias ChatApiWeb.{
    AccountSettingsJSON,
    UserJSON,
    WidgetSettingsJSON,
    WorkingHoursJSON
  }

  def index(%{accounts: accounts}) do
    %{data: Enum.map(accounts, &account/1)}
  end

  def show(%{account: account}) do
    %{data: maybe(account, &account/1)}
  end

  def create(%{account: account}) do
    %{data: maybe(account, &basic/1)}
  end

  def basic(account) do
    %{
      object: "account",
      id: account.id,
      company_name: account.company_name,
      company_logo_url: account.company_logo_url,
      time_zone: account.time_zone,
      subscription_plan: account.subscription_plan,
      settings: maybe(account.settings, &AccountSettingsJSON.account_settings/1),
      working_hours: Enum.map(account.working_hours, &WorkingHoursJSON.working_hours/1),
      # TODO: not sure if this logic should be handled on the client instead, but this simplifies things for now
      is_outside_working_hours: Accounts.is_outside_working_hours?(account),
      current_minutes_since_midnight:
        Utils.DateTimeUtils.current_minutes_since_midnight(account.time_zone)
    }
  end

  def account(account) do
    %{
      object: "account",
      id: account.id,
      company_name: account.company_name,
      company_logo_url: account.company_logo_url,
      time_zone: account.time_zone,
      subscription_plan: account.subscription_plan,
      settings: maybe(account.settings, &AccountSettingsJSON.account_settings/1),
      users: Enum.map(account.users, &UserJSON.user/1),
      # TODO: get rid of this?
      widget_settings: Enum.map(account.widget_settings, &WidgetSettingsJSON.basic/1),
      working_hours: Enum.map(account.working_hours, &WorkingHoursJSON.working_hours/1),
      # TODO: not sure if this logic should be handled on the client instead, but this simplifies things for now
      is_outside_working_hours: Accounts.is_outside_working_hours?(account),
      current_minutes_since_midnight:
        Utils.DateTimeUtils.current_minutes_since_midnight(account.time_zone)
    }
  end
end
