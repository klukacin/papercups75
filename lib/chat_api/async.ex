defmodule ChatApi.Async do
  @moduledoc """
  Small indirection for fire-and-forget background work.

  In prod/dev this spawns an unlinked `Task` (same as a bare `Task.start/1`).
  In the test environment it runs the function synchronously, so any database
  work inside it completes within the test's checked-out SQL Sandbox connection
  instead of racing the test's teardown (which caused intermittent
  `DBConnection.OwnershipError` flakiness). Controlled by the
  `:run_async_tasks` application env (defaults to `true`; set to `false` in
  `config/test.exs`).
  """

  @spec run((-> any())) :: {:ok, pid()} | :ok
  def run(fun) when is_function(fun, 0) do
    if Application.get_env(:chat_api, :run_async_tasks, true) do
      Task.start(fun)
    else
      fun.()
      :ok
    end
  end
end
