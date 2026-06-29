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

# --- 1. System toolchain (precompiled OTP + Elixir, no source builds) ---
# Both Erlang/OTP and Elixir come from official *precompiled* releases, so
# nothing is built from source on each ephemeral container:
#   - OTP from builds.hex.pm (the same artifacts setup-beam uses in CI)
#   - Elixir from the elixir-lang GitHub release built for the matching OTP
# We use OTP 27 so current deps compile (e.g. jose >= 1.11.10 uses the OTP 26
# `dynamic()` type). The full OTP tarball includes parsetools (yecc headers)
# and xmerl, which some Hex packages need.
OTP_DIR=/opt/otp
ELIXIR_DIR=/opt/elixir
OTP_VERSION=27.3.4.13
ELIXIR_VERSION=1.18.4

# Runtime libraries the precompiled OTP links against (OpenSSL 3, ncurses/tinfo)
# plus the download tools.
as_root apt-get update -qq
as_root apt-get install -y -q libssl3 libtinfo6 ca-certificates curl unzip

if [ ! -x "$OTP_DIR/bin/erl" ]; then
  log "Installing precompiled Erlang/OTP ${OTP_VERSION}..."
  TMP_TGZ="$(mktemp)"
  curl -fsSL -o "$TMP_TGZ" \
    "https://builds.hex.pm/builds/otp/ubuntu-24.04/OTP-${OTP_VERSION}.tar.gz"
  as_root mkdir -p "$OTP_DIR"
  as_root tar -xzf "$TMP_TGZ" -C "$OTP_DIR" --strip-components=1
  rm -f "$TMP_TGZ"
  # Fix the absolute paths baked into the OTP scripts (erl, etc.).
  (cd "$OTP_DIR" && as_root ./Install -minimal "$OTP_DIR" >/dev/null)
fi

export PATH="$OTP_DIR/bin:$PATH"

if [ ! -x "$ELIXIR_DIR/bin/elixir" ]; then
  log "Installing precompiled Elixir ${ELIXIR_VERSION} (OTP 27)..."
  TMP_ZIP="$(mktemp)"
  curl -fsSL -o "$TMP_ZIP" \
    "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-27.zip"
  as_root mkdir -p "$ELIXIR_DIR"
  as_root unzip -oq "$TMP_ZIP" -d "$ELIXIR_DIR"
  rm -f "$TMP_ZIP"
fi

# Put Erlang + Elixir on PATH and set a UTF-8 locale (+fnu avoids latin1
# name-encoding warnings) for the rest of this script...
export PATH="$ELIXIR_DIR/bin:$PATH"
export LANG="${LANG:-C.UTF-8}" LC_ALL="${LC_ALL:-C.UTF-8}" ELIXIR_ERL_OPTIONS="+fnu"

# ...and persist it for the rest of the session (the agent's later shells).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$OTP_DIR/bin:$ELIXIR_DIR/bin:\$PATH\""
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
  as_root pg_ctlcluster "$PG_VER" main start || true
  # Give the postgres role the password the dev/test config expects. The
  # default localhost scram-sha-256 auth works with the upgraded Postgrex.
  psql_postgres "ALTER USER postgres PASSWORD 'postgres';" >/dev/null 2>&1 || true
fi

# --- 4. Elixir dependencies ----------------------------------------------
log "Fetching Elixir dependencies..."
mix deps.get

# --- 5. Frontend dependencies --------------------------------------------
if [ -f assets/package.json ]; then
  log "Installing frontend dependencies..."
  npm install --prefix=assets --legacy-peer-deps --no-audit --no-fund
fi

log "Setup complete."
