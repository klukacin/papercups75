defmodule ChatApiWeb.LambdaJSON do
  import ChatApiWeb.JSONHelpers

  def index(%{lambdas: lambdas}) do
    %{data: Enum.map(lambdas, &lambda/1)}
  end

  def show(%{lambda: lambda}) do
    %{data: maybe(lambda, &lambda/1)}
  end

  def lambda(lambda) do
    %{
      id: lambda.id,
      object: "lambda",
      created_at: lambda.inserted_at,
      updated_at: lambda.updated_at,
      account_id: lambda.account_id,
      name: lambda.name,
      description: lambda.description,
      code: lambda.code,
      language: lambda.language,
      runtime: lambda.runtime,
      status: lambda.status,
      last_deployed_at: lambda.last_deployed_at,
      last_executed_at: lambda.last_executed_at,
      metadata: lambda.metadata
    }
  end
end
