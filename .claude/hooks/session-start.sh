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

# --- 1. System toolchain (Erlang via apt, Elixir via precompiled release) ---
# Erlang/OTP comes from apt: installs in seconds and provides OTP 25 plus:
#   erlang-nox  - full runtime minus GUI/wx (xmerl etc. that sweet_xml needs);
#                 the GUI 'erlang' meta-package pulls wx and currently 404s.
#   erlang-dev  - yecc/leex headers (yeccpre.hrl) some Hex packages need.
# Elixir is installed from the official *precompiled* release that runs on
# OTP 25. This gives a modern Elixir (1.18) without compiling Erlang from
# source on every ephemeral container. Modern deps (e.g. plug 1.20) need
# Elixir >= 1.15, so apt's older Elixir is not enough.
ELIXIR_DIR=/opt/elixir
ELIXIR_VERSION=1.18.4

if ! command -v erl >/dev/null 2>&1; then
  log "Installing Erlang/OTP via apt..."
  as_root apt-get update -qq
  as_root apt-get install -y -q erlang-nox erlang-dev curl unzip ca-certificates
fi

if [ ! -x "$ELIXIR_DIR/bin/elixir" ]; then
  log "Installing precompiled Elixir ${ELIXIR_VERSION} (OTP 25)..."
  TMP_ZIP="$(mktemp)"
  curl -fsSL -o "$TMP_ZIP" \
    "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-25.zip"
  as_root mkdir -p "$ELIXIR_DIR"
  as_root unzip -oq "$TMP_ZIP" -d "$ELIXIR_DIR"
  rm -f "$TMP_ZIP"
fi

# Put Elixir on PATH and set a UTF-8 locale (+fnu avoids latin1 name-encoding
# warnings) for the rest of this script...
export PATH="$ELIXIR_DIR/bin:$PATH"
export LANG="${LANG:-C.UTF-8}" LC_ALL="${LC_ALL:-C.UTF-8}" ELIXIR_ERL_OPTIONS="+fnu"

# ...and persist it for the rest of the session (the agent's later shells).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$ELIXIR_DIR/bin:\$PATH\""
    echo "export LANG=C.UTF-8"
    echo "export LC_ALL=C.UTF-8"
    echo "export ELIXIR_ERL_OPTIONS=+fnu"
  } >> "$CLAUDE_ENV_FILE"
fi

log "Using $("$ELIXIR_DIR/bin/elixir" --version | tail -1)"

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
