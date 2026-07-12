defmodule ChatApi.EmailAccounts.Client do
  @moduledoc """
  A thin IMAP/SMTP client wrapper used to verify email account credentials.

  Workers and controllers should always go through this module (and tests
  mock it) rather than talking to `Mailroom.IMAP` / `:gen_smtp_client`
  directly.

  ## TLS notes

    * `imap_tls`/`smtp_tls` accept `"ssl"` (implicit TLS on connect),
      `"starttls"` (plain connect upgraded via STARTTLS) and `"none"`.
    * mailroom (IMAP) performs the STARTTLS upgrade automatically during
      login whenever the server advertises the capability; the `ssl_opts` we
      pass to `Mailroom.IMAP.connect/4` are reused for that upgrade. When
      `imap_tls` is `"starttls"` we additionally check that the connection
      was actually upgraded and fail verification otherwise (so credentials
      are not silently accepted over plaintext).
    * mailroom's and gen_smtp's default TLS options are insecure
      (certificate chain `depth: 0` and no CA store), so we always pass
      explicit options: `verify_peer`, the OS trust store via
      `:public_key.cacerts_get/0`, SNI and `depth: 3`. Setting
      `settings["allow_insecure_tls"]` on the email account downgrades this
      to `verify: :verify_none` for self-signed/internal servers.
  """

  alias ChatApi.EmailAccounts
  alias ChatApi.EmailAccounts.EmailAccount

  @verify_timeout 30_000

  @config_fields [
    :from_address,
    :imap_host,
    :imap_port,
    :imap_tls,
    :imap_username,
    :imap_password,
    :imap_folder,
    :smtp_host,
    :smtp_port,
    :smtp_tls,
    :smtp_username,
    :smtp_password,
    :settings
  ]

  @doc """
  Verifies the IMAP settings by connecting, logging in and selecting the
  configured folder. Returns `{:ok, %{exists: n}}` with the number of
  messages in the folder, or `{:error, reason}` with a human-readable reason.

  Accepts either a stored `%EmailAccount{}` or a plain attrs map (with
  string or atom keys), so credentials can be verified before saving.
  """
  @spec verify_imap(EmailAccount.t() | map()) ::
          {:ok, %{exists: non_neg_integer()}} | {:error, String.t()}
  def verify_imap(config) do
    %EmailAccount{} = email_account = normalize(config)

    cond do
      blank?(email_account.imap_host) ->
        {:error, "IMAP host is required"}

      blank?(email_account.imap_username) ->
        {:error, "IMAP username is required"}

      blank?(email_account.imap_password) ->
        {:error, "IMAP password is required"}

      true ->
        run_isolated(fn -> do_verify_imap(email_account) end)
    end
  end

  @doc """
  Verifies the SMTP settings by opening an (authenticated) session and
  closing it again — no email is sent. Returns `:ok` or `{:error, reason}`.
  """
  @spec verify_smtp(EmailAccount.t() | map()) :: :ok | {:error, String.t()}
  def verify_smtp(config) do
    %EmailAccount{} = email_account = normalize(config)

    cond do
      blank?(email_account.smtp_host) ->
        {:error, "SMTP host is required"}

      blank?(EmailAccounts.smtp_username(email_account)) ->
        {:error, "SMTP username is required (or provide IMAP credentials to fall back to)"}

      blank?(EmailAccounts.smtp_password(email_account)) ->
        {:error, "SMTP password is required (or provide IMAP credentials to fall back to)"}

      true ->
        run_isolated(fn -> do_verify_smtp(email_account) end)
    end
  end

  @doc """
  Builds the options passed to `Mailroom.IMAP.connect/4`. Pure — exposed for
  testing.
  """
  @spec imap_opts(EmailAccount.t() | map()) :: Keyword.t()
  def imap_opts(config) do
    %EmailAccount{imap_host: host, imap_port: port, imap_tls: tls} =
      email_account = normalize(config)

    ssl_opts =
      case tls do
        # No TLS requested: mailroom still upgrades opportunistically when
        # the server advertises STARTTLS, which should not fail on cert
        # checks for a connection the user asked to be unencrypted.
        "none" -> [verify: :verify_none]
        _other -> ssl_opts(host, email_account.settings)
      end

    [ssl: tls == "ssl", port: port, ssl_opts: ssl_opts]
  end

  @doc """
  Builds the options passed to `:gen_smtp_client.open/1`. Pure — exposed for
  testing.
  """
  @spec smtp_opts(EmailAccount.t() | map()) :: Keyword.t()
  def smtp_opts(config) do
    %EmailAccount{smtp_host: host, smtp_port: port, smtp_tls: tls} =
      email_account = normalize(config)

    base = [
      relay: host,
      port: port,
      auth: :always,
      username: EmailAccounts.smtp_username(email_account),
      password: EmailAccounts.smtp_password(email_account),
      # Connect to the configured host directly instead of resolving MX
      # records for its domain.
      no_mx_lookups: true,
      retries: 0,
      timeout: 15_000
    ]

    case tls do
      "ssl" ->
        # gen_smtp only applies :tls_options on the STARTTLS upgrade path;
        # an implicit ssl connect takes its ssl options from :sockopts.
        base ++ [ssl: true, tls: :never, sockopts: ssl_opts(host, email_account.settings)]

      "starttls" ->
        base ++ [ssl: false, tls: :always, tls_options: ssl_opts(host, email_account.settings)]

      "none" ->
        base ++ [ssl: false, tls: :never]
    end
  end

  @doc """
  Normalizes a stored `%EmailAccount{}` or a plain attrs map (string or atom
  keys) into an `%EmailAccount{}` struct, applying the schema defaults for
  any missing/blank fields.
  """
  @spec normalize(EmailAccount.t() | map()) :: EmailAccount.t()
  def normalize(%EmailAccount{} = email_account), do: email_account

  def normalize(attrs) when is_map(attrs) do
    fields =
      for field <- @config_fields,
          value = Map.get(attrs, field, Map.get(attrs, Atom.to_string(field))),
          not blank?(value) do
        coerce_field(field, value)
      end

    struct(EmailAccount, fields)
  end

  ## IMAP

  defp do_verify_imap(%EmailAccount{} = email_account) do
    opts = imap_opts(email_account)
    folder = presence(email_account.imap_folder) || "INBOX"

    case Mailroom.IMAP.connect(
           email_account.imap_host,
           email_account.imap_username,
           email_account.imap_password,
           opts
         ) do
      {:ok, client} ->
        try do
          with :ok <- ensure_starttls_upgraded(client, email_account),
               {:ok, _msg} <- select_folder(client, folder) do
            {:ok, %{exists: Mailroom.IMAP.email_count(client)}}
          end
        after
          safe_logout(client)
        end

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  # `Mailroom.IMAP.select/2` swallows errors (it returns the pid even when
  # the server replies NO), so we issue the underlying call directly to know
  # whether the folder could actually be opened.
  defp select_folder(client, folder) do
    case GenServer.call(client, {:select, folder}) do
      {:ok, msg} -> {:ok, msg}
      {:error, reason} -> {:error, "Could not open folder #{folder}: #{format_reason(reason)}"}
    end
  end

  # For "starttls" we require that mailroom actually upgraded the socket
  # (it only does so when the server advertises the STARTTLS capability —
  # otherwise it logs in over plaintext, which the user did not ask for).
  defp ensure_starttls_upgraded(client, %EmailAccount{imap_tls: "starttls"}) do
    case :sys.get_state(client) do
      %{socket: %Mailroom.Socket{ssl: false}} ->
        {:error,
         "IMAP server did not offer STARTTLS — use SSL (usually port 993) or \"none\" instead"}

      _upgraded_or_unknown ->
        :ok
    end
  catch
    # Defensive: introspection depends on mailroom internals.
    _kind, _reason -> :ok
  end

  defp ensure_starttls_upgraded(_client, _email_account), do: :ok

  defp safe_logout(client) do
    Mailroom.IMAP.logout(client)
    :ok
  catch
    _kind, _reason -> :ok
  end

  ## SMTP

  defp do_verify_smtp(%EmailAccount{} = email_account) do
    case :gen_smtp_client.open(smtp_opts(email_account)) do
      {:ok, socket} ->
        safe_smtp_close(socket)
        :ok

      {:error, :bad_option, reason} ->
        {:error, "Invalid SMTP options: #{inspect(reason)}"}

      {:error, _type, failure} ->
        {:error, format_smtp_failure(failure)}

      other ->
        {:error, format_reason(other)}
    end
  end

  defp safe_smtp_close(socket) do
    :gen_smtp_client.close(socket)
    :ok
  catch
    _kind, _reason -> :ok
  end

  defp format_smtp_failure({:permanent_failure, _host, :auth_failed}),
    do: "SMTP authentication failed — check the username and password"

  defp format_smtp_failure({:permanent_failure, _host, message}),
    do: "SMTP error: #{format_reason(message)}"

  defp format_smtp_failure({:temporary_failure, _host, :tls_failed}),
    do: "SMTP TLS negotiation failed"

  defp format_smtp_failure({:temporary_failure, _host, message}),
    do: "SMTP error: #{format_reason(message)}"

  defp format_smtp_failure({:missing_requirement, _host, :auth}),
    do: "SMTP server does not support authentication"

  defp format_smtp_failure({:missing_requirement, _host, :tls}),
    do: "SMTP server does not support STARTTLS — try SSL or \"none\" instead"

  defp format_smtp_failure({:network_failure, _host, {:error, reason}}),
    do: format_reason(reason)

  defp format_smtp_failure({:unexpected_response, _host, response}),
    do: "Unexpected SMTP response: #{inspect(response)}"

  defp format_smtp_failure(other), do: format_reason(other)

  ## Shared helpers

  defp ssl_opts(host, settings) do
    if allow_insecure_tls?(settings) do
      [verify: :verify_none]
    else
      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(host),
        # mailroom/gen_smtp default to depth: 0, which rejects any chain
        # with intermediate certificates; 3 matches common practice.
        depth: 3
      ]
    end
  end

  defp allow_insecure_tls?(settings) when is_map(settings) do
    Map.get(settings, "allow_insecure_tls", Map.get(settings, :allow_insecure_tls)) in [
      true,
      "true"
    ]
  end

  defp allow_insecure_tls?(_settings), do: false

  # Runs the (blocking, socket-opening) verification in a monitored child
  # process. mailroom's IMAP GenServer is linked to its caller and raises on
  # e.g. a BAD response, so verification must be isolated to guarantee we
  # always return `{:error, reason}` instead of crashing (or hanging) the
  # caller.
  defp run_isolated(fun, timeout \\ @verify_timeout) do
    parent = self()
    ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        # Trap exits so that a crashing linked (mailroom) process turns into
        # a catchable GenServer.call exit instead of killing us silently.
        Process.flag(:trap_exit, true)

        result =
          try do
            fun.()
          rescue
            error -> {:error, format_reason(error)}
          catch
            kind, reason when kind in [:exit, :throw] -> {:error, format_reason(reason)}
          end

        send(parent, {ref, result})
        # Exit abnormally (but quietly) so lingering linked connection
        # processes are shut down with us.
        exit(:shutdown)
      end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, format_reason(reason)}
    after
      timeout ->
        Process.demonitor(monitor_ref, [:flush])
        Process.exit(pid, :kill)
        {:error, "Connection verification timed out"}
    end
  end

  defp format_reason(message) when is_binary(message), do: String.trim(message)

  defp format_reason({:authentication, reason}),
    do: "Authentication failed: #{format_reason(reason)}"

  defp format_reason(:unable_to_connect), do: "Unable to connect to server — check host and port"
  defp format_reason(:timeout), do: "Connection timed out"
  defp format_reason(:etimedout), do: "Connection timed out"
  defp format_reason(:nxdomain), do: "Could not resolve server hostname"
  defp format_reason(:econnrefused), do: "Connection refused — check host and port"
  defp format_reason(:ehostunreach), do: "Server is unreachable"
  defp format_reason(:closed), do: "Connection closed by server"
  defp format_reason(:econnreset), do: "Connection reset by server"

  defp format_reason({:tls_alert, {_alert, description}}),
    do: "TLS error: #{format_reason(to_string(description))}"

  defp format_reason({:error, reason}), do: format_reason(reason)
  defp format_reason({:badmatch, {:error, reason}}), do: format_reason(reason)
  defp format_reason({:timeout, {GenServer, :call, _args}}), do: "Connection timed out"
  defp format_reason({reason, {GenServer, :call, _args}}), do: format_reason(reason)

  # Exit reasons from crashes come as {reason, stacktrace}
  defp format_reason({reason, [{_m, _f, _a, _meta} | _] = _stacktrace}),
    do: format_reason(reason)

  defp format_reason(%MatchError{term: {:error, reason}}), do: format_reason(reason)

  defp format_reason(exception) when is_exception(exception), do: Exception.message(exception)

  defp format_reason(other), do: inspect(other)

  defp coerce_field(field, value) when field in [:imap_port, :smtp_port] and is_binary(value) do
    case Integer.parse(value) do
      {port, ""} -> {field, port}
      _other -> {field, value}
    end
  end

  defp coerce_field(field, value), do: {field, value}

  defp blank?(value), do: value in [nil, ""]

  defp presence(value), do: if(blank?(value), do: nil, else: value)
end
