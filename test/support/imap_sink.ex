defmodule ChatApi.ImapSink do
  @moduledoc """
  A tiny scripted IMAP server used to exercise
  `ChatApi.EmailAccounts.Client.fetch_unseen/2` / `mark_seen/2` against a
  real (plaintext) socket.

  It speaks exactly the subset of IMAP4rev1 the client uses — `LOGIN`,
  `SELECT`, `UID SEARCH UNSEEN`, `UID FETCH <uid> (BODY.PEEK[])`,
  `UID STORE ... +FLAGS.SILENT (\\Seen)` and `LOGOUT` — and forwards every
  received command line to the process that started it as
  `{:imap_sink, command_line}` so tests can assert on the wire protocol.

  Start one on an ephemeral localhost port with:

      {:ok, port} =
        ChatApi.ImapSink.start(
          messages: %{5 => raw_binary, 7 => other_raw},
          unseen: [5, 7]
        )

  Options:

    * `:messages` — map of uid => raw message binary (served by `UID FETCH`)
    * `:unseen` — uids reported by `UID SEARCH UNSEEN` (defaults to the
      sorted keys of `:messages`)
    * `:deny` — list of command prefixes (e.g. `["LOGIN", "SELECT"]`) the
      server answers with a tagged `NO`
  """

  @recv_timeout 15_000

  @spec start(Keyword.t()) :: {:ok, :inet.port_number()}
  def start(opts \\ []) do
    messages = Keyword.get(opts, :messages, %{})

    state = %{
      messages: messages,
      unseen: Keyword.get(opts, :unseen, messages |> Map.keys() |> Enum.sort()),
      deny: Keyword.get(opts, :deny, []),
      parent: self()
    }

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)

    # Linked to the test process: crashes surface in the test, and the
    # listener dies (closing the socket) when the test finishes.
    spawn_link(fn -> accept_loop(listen, state) end)

    {:ok, port}
  end

  defp accept_loop(listen, state) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        :ok = :gen_tcp.send(socket, "* OK [CAPABILITY IMAP4rev1] ChatApi.ImapSink ready\r\n")
        serve(socket, state)
        accept_loop(listen, state)

      {:error, _closed} ->
        :ok
    end
  end

  defp serve(socket, state) do
    case :gen_tcp.recv(socket, 0, @recv_timeout) do
      {:ok, line} ->
        [tag, command] =
          case line |> String.trim_trailing() |> String.split(" ", parts: 2) do
            [tag, command] -> [tag, command]
            [tag] -> [tag, ""]
          end

        send(state.parent, {:imap_sink, command})

        case handle_command(command, tag, socket, state) do
          :logout -> :gen_tcp.close(socket)
          :ok -> serve(socket, state)
        end

      {:error, _closed_or_timeout} ->
        :ok
    end
  end

  defp handle_command(command, tag, socket, state) do
    cond do
      denied?(command, state) ->
        reply(socket, "#{tag} NO #{verb(command)} denied by test script")

      match?("LOGIN" <> _, command) ->
        reply(socket, "#{tag} OK LOGIN completed")

      match?("CAPABILITY" <> _, command) ->
        reply(socket, "* CAPABILITY IMAP4rev1\r\n#{tag} OK CAPABILITY completed")

      match?("SELECT" <> _, command) ->
        reply(
          socket,
          Enum.join(
            [
              "* #{map_size(state.messages)} EXISTS",
              "* 0 RECENT",
              "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)",
              "* OK [UIDVALIDITY 1] UIDs valid",
              "#{tag} OK [READ-WRITE] SELECT completed"
            ],
            "\r\n"
          )
        )

      match?("UID SEARCH" <> _, command) ->
        search =
          case state.unseen do
            [] -> "* SEARCH"
            uids -> "* SEARCH #{Enum.join(uids, " ")}"
          end

        reply(socket, "#{search}\r\n#{tag} OK SEARCH completed")

      match?("UID FETCH" <> _, command) ->
        [_full, uid] = Regex.run(~r/^UID FETCH (\d+)/, command)
        uid = String.to_integer(uid)
        raw = Map.fetch!(state.messages, uid)

        :ok =
          :gen_tcp.send(socket, [
            "* 1 FETCH (UID #{uid} BODY[] {#{byte_size(raw)}}\r\n",
            raw,
            ")\r\n",
            "#{tag} OK FETCH completed\r\n"
          ])

        :ok

      match?("UID STORE" <> _, command) ->
        reply(socket, "#{tag} OK STORE completed")

      match?("LOGOUT" <> _, command) ->
        reply(socket, "* BYE ChatApi.ImapSink logging out\r\n#{tag} OK LOGOUT completed")
        :logout

      true ->
        reply(socket, "#{tag} BAD Unknown command")
    end
  end

  defp denied?(command, %{deny: deny}),
    do: Enum.any?(deny, &String.starts_with?(command, &1))

  defp verb(command), do: command |> String.split(" ", parts: 2) |> hd()

  defp reply(socket, response) do
    :ok = :gen_tcp.send(socket, response <> "\r\n")
    :ok
  end
end
