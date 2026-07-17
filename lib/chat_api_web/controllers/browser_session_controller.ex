defmodule ChatApiWeb.BrowserSessionController do
  use ChatApiWeb, :controller

  alias ChatApi.Accounts
  alias ChatApi.BrowserSessions
  alias ChatApi.BrowserSessions.BrowserSession

  action_fallback ChatApiWeb.FallbackController

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn) do
      browser_sessions = BrowserSessions.list_browser_sessions(account_id, params)

      render(conn, :index, browser_sessions: browser_sessions)
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"browser_session" => browser_session_params}) do
    with {:ok, %BrowserSession{} = browser_session} <-
           BrowserSessions.create_browser_session(browser_session_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.browser_session_path(conn, :show, browser_session))
      |> render(:create, browser_session: browser_session)
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn) do
      browser_session = BrowserSessions.get_browser_session!(id, account_id)
      render(conn, :show, browser_session: browser_session)
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id, "browser_session" => browser_session_params}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %BrowserSession{account_id: ^account_id} = browser_session <-
           BrowserSessions.get_browser_session!(id),
         {:ok, %BrowserSession{} = browser_session} <-
           BrowserSessions.update_browser_session(browser_session, browser_session_params) do
      render(conn, :create, browser_session: browser_session)
    else
      %BrowserSession{} -> {:error, :not_found}
      other -> other
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn),
         %BrowserSession{account_id: ^account_id} = browser_session <-
           BrowserSessions.get_browser_session!(id),
         {:ok, %BrowserSession{}} <- BrowserSessions.delete_browser_session(browser_session) do
      send_resp(conn, :no_content, "")
    else
      %BrowserSession{} -> {:error, :not_found}
      other -> other
    end
  end

  @spec count(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def count(conn, params) do
    with account_id when not is_nil(account_id) <- Accounts.get_current_account_id(conn) do
      json(conn, %{
        data: %{
          count: BrowserSessions.count_browser_sessions(account_id, params)
        }
      })
    end
  end

  @spec finish(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def finish(conn, %{"id" => id}) do
    browser_session = BrowserSessions.get_browser_session!(id)
    updates = %{finished_at: DateTime.utc_now()}

    with {:ok, %BrowserSession{} = browser_session} <-
           BrowserSessions.update_browser_session(browser_session, updates) do
      render(conn, :create, browser_session: browser_session)
    end
  end

  @spec restart(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def restart(conn, %{"id" => id}) do
    browser_session = BrowserSessions.get_browser_session!(id)
    updates = %{finished_at: nil}

    with {:ok, %BrowserSession{} = browser_session} <-
           BrowserSessions.update_browser_session(browser_session, updates) do
      render(conn, :create, browser_session: browser_session)
    end
  end

  @spec identify(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def identify(conn, %{"id" => id, "customer_id" => customer_id}) do
    browser_session = BrowserSessions.get_browser_session!(id)
    updates = %{customer_id: customer_id}

    with {:ok, %BrowserSession{} = browser_session} <-
           BrowserSessions.update_browser_session(browser_session, updates) do
      render(conn, :create, browser_session: browser_session)
    end
  end

  @spec exists(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def exists(conn, %{"id" => id}) do
    json(conn, %{data: BrowserSessions.exists?(id)})
  end
end
