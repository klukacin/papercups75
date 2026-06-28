# Exclude integration tests that hit real AWS Lambda (tagged
# :lambda_development); they require live AWS credentials and network access.
ExUnit.start(exclude: [:lambda_development])
Ecto.Adapters.SQL.Sandbox.mode(ChatApi.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:ex_machina)
