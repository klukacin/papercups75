defmodule ChatApiWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use ChatApiWeb, :controller

  alias Ecto.Changeset
  alias ChatApiWeb.ErrorHelpers

  # This clause is an example of how to handle resources that cannot be found.
  @spec call(Plug.Conn.t(), tuple()) :: Plug.Conn.t()
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(404)
    |> json(%{
      error: %{
        status: 404,
        message: "Not found"
      }
    })
  end

  def call(conn, {:error, :not_found, message}) do
    conn
    |> put_status(404)
    |> json(%{
      error: %{
        status: 404,
        message: message
      }
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = Changeset.traverse_errors(changeset, &ErrorHelpers.translate_error/1)

    conn
    |> put_status(422)
    |> json(%{
      error: %{
        status: 422,
        message: "Unprocessable Entity",
        errors: errors
      }
    })
  end

  def call(conn, {:error, %Stripe.Error{} = err}) do
    status = (is_map(err.extra) && err.extra[:http_status]) || 502

    conn
    |> put_status(status)
    |> json(%{
      error: %{
        status: status,
        message: err.user_message || err.message || "Billing service error"
      }
    })
  end

  def call(conn, {:error, :unprocessable_entity, message}) do
    conn
    |> put_status(422)
    |> json(%{
      error: %{
        status: 422,
        message: message
      }
    })
  end

  def call(conn, {:error, :forbidden, message}) do
    conn
    |> put_status(403)
    |> json(%{
      error: %{
        status: 403,
        message: message
      }
    })
  end
end
