#!/bin/bash
# SessionStart hook for papercups75.
# Installs the Elixir/Erlang + Node toolchain and project dependencies, and
# brings up a local Postgres so the backend can be compiled, linted and tested
# inside Claude Code on the web sessions.
#
# Synchronous (not async): the session waits until setup is done so the agent
# never races ahead of the toolchain being ready.
set -euo pipefail

# Only run inside the remote (web) environment; locally the developer manages
# their own toolchain (asdf/.tool-versions).
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR"

# Run a command as root whether or not we already are root.
as_root() { if [ "$(id -u)" = "0" ]; then "$@"; else sudo "$@"; fi; }

# Run a psql command as the postgres OS/DB superuser.
psql_postgres() { as_root su - postgres -c "psql -tAc \"$1\""; }

log() { echo "[session-start] $*"; }

# --- 1. System toolchain (Elixir/Erlang) ----------------------------------
# Ubuntu's packaged Elixir/Erlang installs in seconds and is capable of
# building both the current app and the target Phoenix upgrade. (A newer
# Elixir/OTP would have to compile Erlang from source on every ephemeral
# container, which is slow and fragile.)
if ! command -v elixir >/dev/null 2>&1; then
  log "Installing Elixir/Erlang via apt..."
  as_root apt-get update -qq
  # erlang-nox: full Erlang runtime minus GUI/wx (provides xmerl, etc. that
  #   deps like sweet_xml need). The GUI 'erlang' meta-package pulls wx and
  #   currently 404s, so we deliberately use the -nox variant.
  # erlang-dev: yecc/leex headers (yeccpre.hrl) that some Hex packages
  #   (e.g. earmark_parser) need to compile their grammars.
  as_root apt-get install -y -q elixir erlang-nox erlang-dev
else
  log "Elixir already present: $(elixir --version | tail -1)"
fi

# --- 2. Hex + Rebar -------------------------------------------------------
log "Ensuring Hex and Rebar are installed..."
mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null

# --- 3. Postgres (needed for ecto.create / mix test) ----------------------
if command -v pg_ctlcluster >/dev/null 2>&1; then
  log "Starting Postgres..."
  PG_VER="$(pg_lsclusters -h | awk 'NR==1{print $1}')"
  # The Postgrex version pinned for the current app predates Postgres 16's
  # default scram-sha-256 auth and dies with {:case_clause, []} against it.
  # Switch localhost auth to trust so the dev/test DB connections work without
  # touching the locked dependency. (Local dev container only.)
  HBA="/etc/postgresql/${PG_VER}/main/pg_hba.conf"
  if [ -f "$HBA" ]; then
    as_root sed -i -E 's|^(host[[:space:]]+all[[:space:]]+all[[:space:]]+(127\.0\.0\.1/32|::1/128)[[:space:]]+)scram-sha-256|\1trust|' "$HBA"
  fi
  as_root pg_ctlcluster "$PG_VER" main start || true
  psql_postgres "SELECT pg_reload_conf();" >/dev/null 2>&1 || true
  # Keep a password on the role too, in case auth is later tightened.
  psql_postgres "ALTER USER postgres PASSWORD 'postgres';" >/dev/null 2>&1 || true
fi

# --- 4. Elixir dependencies ----------------------------------------------
log "Fetching Elixir dependencies..."
mix deps.get

# --- 5. Frontend dependencies --------------------------------------------
if [ -f assets/package.json ]; then
  log "Installing frontend dependencies..."
  npm install --prefix=assets --no-audit --no-fund
fi

log "Setup complete."
