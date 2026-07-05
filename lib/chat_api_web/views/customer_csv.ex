defmodule ChatApiWeb.CustomerCSV do
  alias ChatApiWeb.{CSVHelpers, CustomerJSON}

  @customer_csv_ordered_fields ~w(id name email created_at updated_at)a ++
                                 ~w(first_seen last_seen_at phone external_id)a ++
                                 ~w(host pathname current_url browser)a ++
                                 ~w(os ip time_zone)a

  def index(%{page: page}) do
    page.entries
    |> Enum.map(&CustomerJSON.customer/1)
    |> CSVHelpers.dump_csv_rfc4180(@customer_csv_ordered_fields)
  end
end
