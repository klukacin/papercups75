defmodule ChatApi.SmtpSink do
  @moduledoc """
  A minimal `gen_smtp_server_session` callback module used to run a real
  in-BEAM SMTP server in tests.

  The sink advertises `AUTH PLAIN LOGIN` and accepts *any* credentials (so
  the client's `auth: :always` path is exercised end-to-end without real
  accounts), accepts any sender/recipient, and forwards every received
  message to the process configured via `callbackoptions[:forward_to]` as:

      {:smtp_sink, %{from: from, to: to, data: data}}

  where `data` is the raw RFC 5322 message received in the `DATA` command.

  Start one on an ephemeral localhost port with:

      {:ok, _pid} =
        :gen_smtp_server.start(name, ChatApi.SmtpSink,
          port: 0,
          address: {127, 0, 0, 1},
          sessionoptions: [callbackoptions: [forward_to: self()]]
        )

      port = :ranch.get_port(name)
  """

  @behaviour :gen_smtp_server_session

  @impl true
  def init(hostname, _session_count, _peer_address, options) do
    {:ok, "#{hostname} ESMTP ChatApi.SmtpSink", %{options: options}}
  end

  @impl true
  def handle_HELO(_hostname, state), do: {:ok, state}

  @impl true
  def handle_EHLO(_hostname, extensions, state) do
    {:ok, extensions ++ [{~c"AUTH", ~c"PLAIN LOGIN"}], state}
  end

  # Accept any username/password: tests only need the AUTH exchange to
  # happen, not real credential checking.
  @impl true
  def handle_AUTH(type, _username, _password, state) when type in [:plain, :login],
    do: {:ok, state}

  def handle_AUTH(_type, _username, _password, _state), do: :error

  @impl true
  def handle_MAIL(_from, state), do: {:ok, state}

  @impl true
  def handle_MAIL_extension(_extension, _state), do: :error

  @impl true
  def handle_RCPT(_to, state), do: {:ok, state}

  @impl true
  def handle_RCPT_extension(_extension, _state), do: :error

  @impl true
  def handle_DATA(from, to, data, %{options: options} = state) do
    case Keyword.get(options, :forward_to) do
      pid when is_pid(pid) -> send(pid, {:smtp_sink, %{from: from, to: to, data: data}})
      _ -> :ok
    end

    {:ok, "queued as #{System.unique_integer([:positive])}", state}
  end

  @impl true
  def handle_RSET(state), do: state

  @impl true
  def handle_VRFY(_address, state), do: {:error, "252 VRFY disabled", state}

  @impl true
  def handle_other(verb, _args, state),
    do: {["500 Error: command not recognized : '", verb, "'"], state}

  @impl true
  def handle_STARTTLS(state), do: state

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  @impl true
  def terminate(reason, state), do: {:ok, reason, state}
end
