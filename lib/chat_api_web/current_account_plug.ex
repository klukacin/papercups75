defmodule ChatApiWeb.CurrentAccountPlug do
  @moduledoc """
  Resolves which account the current request is for and assigns it as
  `conn.assigns.current_account_id` (Phase B multi-account membership).

  This plug must run AFTER authentication. It expects `conn.assigns.current_user`
  to be set; if it is nil, the conn is returned unchanged so the normal auth
  error handling applies.

  The target account id is resolved from the `x-account-id` request header, or
  falls back to the user's primary `account_id` (keeping single-account behavior
  identical).

  Before assigning, membership is verified via
  `ChatApi.Accounts.user_member_of?/2`. If the user is not a member of the
  resolved account, the request is halted with a 403 response.

  ## Example

      plug ChatApiWeb.CurrentAccountPlug
  """
  import Plug.Conn, only: [get_req_header: 2, halt: 1, put_status: 2, assign: 3]

  alias Phoenix.Controller
  alias Plug.Conn
  alias ChatApi.Accounts

  @doc false
  @spec init(any()) :: any()
  def init(opts), do: opts

  @doc false
  @spec call(Conn.t(), any()) :: Conn.t()
  def call(conn, _opts \\ []) do
    case conn.assigns[:current_user] do
      nil ->
        conn

      current_user ->
        account_id = resolve_account_id(conn, current_user)

        if Accounts.user_member_of?(current_user, account_id) do
          assign(conn, :current_account_id, account_id)
        else
          forbidden(conn)
        end
    end
  end

  defp resolve_account_id(conn, current_user) do
    case get_req_header(conn, "x-account-id") do
      [account_id | _] when is_binary(account_id) and account_id != "" -> account_id
      _ -> current_user.account_id
    end
  end

  defp forbidden(conn) do
    conn
    |> put_status(403)
    |> Controller.json(%{
      error: %{
        status: 403,
        message: "Forbidden: not a member of this account"
      }
    })
    |> halt()
  end
end
