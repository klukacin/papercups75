# Email channel (generic IMAP/SMTP)

Each inbox can be connected to one email account (Settings → Inboxes →
your inbox → Email). Papercups polls the account's IMAP folder about once a
minute for unseen mail and sends agent replies through the account's SMTP
server. This page documents the operational knobs added for production
hardening.

## Credential encryption at rest (`PAPERCUPS_ENCRYPTION_KEY`)

IMAP/SMTP passwords are encrypted in the database with AES-256-GCM when the
`PAPERCUPS_ENCRYPTION_KEY` environment variable is set. Generate a key and
set it on the server:

```sh
openssl rand -base64 32
# e.g. PAPERCUPS_ENCRYPTION_KEY="qmCzcSKCpZO0Vy1zGCTBTKWDT0OeXjZ3H4Dp2P0X0Uo="
```

Encrypted values are stored as `enc:v1:<base64(iv <> tag <> ciphertext)>`.

Semantics (all handled by `ChatApi.Encryption`):

- **No key set:** passwords are stored and read in plaintext, exactly as
  before; a one-time warning is logged. Nothing breaks for self-hosters who
  skip this step.
- **Key set later:** old plaintext rows keep working (they load unchanged).
  Run `mix encrypt_email_credentials` once to encrypt them in place — the
  task is idempotent (already-encrypted values are untouched) and a no-op
  when the key is missing.
- **Losing or changing the key:** encrypted values can *not* be read without
  the original key — reads fail with a clear error rather than returning
  garbage. Back the key up like a database credential; to rotate it you must
  re-enter the account passwords (or decrypt with the old key first).

## Failure handling, backoff, and recovery

- Every failed poll (connect/fetch error, or a failed mark-as-read — see
  below) increments the account's `failure_count`, records `last_error`
  and stamps `last_failed_at`.
- The minutely fan-out skips accounts that failed recently: the next attempt
  is allowed at `last_failed_at + min(2^failure_count, 60)` minutes —
  2 min after the first failure, then 4, 8, 16, 32, capped at 60 minutes.
- After **10 consecutive failures** the account status flips to `"error"`
  and it stops being polled entirely. The failure reason is shown in the
  inbox's email settings page (`last_error`).
- **Recovery:** fix the underlying problem (password, host, firewall...) and
  press **Test connection** on the stored account. When *both* the IMAP and
  SMTP checks pass, the account's `failure_count`/`last_error`/
  `last_failed_at` are reset and an `"error"` status is set back to
  `"active"`, so polling resumes on the next tick. A failed test changes
  nothing, and a deliberately `"disabled"` account is never re-enabled by a
  test — only its failure bookkeeping is cleared.
- A successful poll also clears the failure state automatically.

## Mark-as-read semantics

Papercups fetches unseen mail with `BODY.PEEK[]` (which does **not** flag
messages) and only marks a message `\Seen` after it reached a terminal
state: ingested, skipped (auto-replies/bulk/self-addressed/oversized),
duplicate, or unparseable. Transient failures (e.g. the database is briefly
down) leave the message unseen so it is retried on the next poll;
Message-ID dedup makes that reprocessing safe (the dedup/threading lookups
are backed by partial indexes on `messages ((metadata->>'email_message_id'))`).

If flagging itself fails, the poll is recorded as a failure (backoff +
`last_error`) — otherwise the account would silently re-download the same
mail forever. Use a dedicated mailbox for Papercups if you don't want the
`\Seen` flags: anything that *unsets* them (another client, a rule) causes
harmless but wasteful re-fetching.

## Message size cap

Raw messages larger than **10 MB** are skipped (and marked seen) without
being parsed, so an attachment bomb cannot be re-downloaded every minute.
Override per account via the `settings` JSON on the email account:

```json
{"max_message_bytes": 26214400}
```

## Provider caveats

- **Office 365 / Outlook:** Basic-auth IMAP/SMTP is disabled by default on
  many tenants (Microsoft is phasing it out in favor of OAuth, which this
  channel does not speak). If login fails with authentication errors even
  though the password is right, your tenant likely requires OAuth — use an
  admin-enabled app password, enable SMTP AUTH for the mailbox
  (`Set-CASMailbox -SmtpClientAuthenticationDisabled $false`), or use a
  different provider.
- **Gmail:** use the native Gmail integration instead where possible. For
  plain IMAP, enable 2FA and generate an **app password**
  (https://myaccount.google.com/apppasswords) — regular account passwords
  are rejected.
- **App passwords in general:** any provider with two-factor auth will
  reject the account password over IMAP/SMTP; always create an app-specific
  password.
- **Self-signed certificates:** TLS is verified against the OS trust store
  by default. For internal servers with self-signed certs set
  `{"allow_insecure_tls": true}` in the account's `settings`.
