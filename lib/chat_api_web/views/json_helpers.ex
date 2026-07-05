defmodule ChatApiWeb.JSONHelpers do
  @moduledoc """
  Helpers for format-based JSON view modules.
  """

  @doc """
  Applies `fun` to `resource`, returning `nil` when the resource is `nil`.

  This replicates the nil-handling behavior of `Phoenix.View.render_one/4`.
  """
  @spec maybe(nil, (any() -> any())) :: nil
  @spec maybe(any(), (any() -> any())) :: any()
  def maybe(nil, _fun), do: nil
  def maybe(resource, fun), do: fun.(resource)
end
