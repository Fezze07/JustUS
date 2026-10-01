#!/usr/bin/env bash
# =============================================================================
# run-sql-tests.sh — execute the Supabase SQL test scripts.
#
# Every supabase/test/*.test.sql is self-contained: it opens a transaction and
# ROLLBACKs at the end, so running them never leaves data behind.
#
# Usage:
#   scripts/run-sql-tests.sh                       # run all discovered tests
#   scripts/run-sql-tests.sh rls_user_isolation retention_cleanup_old_logs  # subset
#
# scripts/test-all.sh always invokes this (one of its four parallel phases);
# it passes no arguments, so every supabase/test/*.test.sql is selected.
#
# Connection resolution (first match wins):
#   1. $DATABASE_URL           — full postgres:// connection string
#   2. $SUPABASE_DB_URL        — Supabase CLI's pooled/direct DB URL
#   3. Derived from $SUPABASE_URL + $SUPABASE_DB_PASSWORD ("postgres" role)
#
# SKIP BEHAVIOUR:
#   With no database configured the script SKIPS (exit 0) instead of failing,
#   so `scripts/test-all.sh` stays usable offline. Set SQL_REQUIRED=1 to turn a
#   missing database into a hard failure (use this in CI).
#
# Each file is run with -v ON_ERROR_STOP=1 and the variable __sql_test_name set,
# so a script can interpolate its own name into failure messages.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SQL_DIR="$REPO_ROOT/supabase/test"

log()  { printf '%s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
err()  { printf '  x %s\n' "$*" >&2; }

# -----------------------------------------------------------------------------
# Resolve a connection string, or explain what is missing.
# -----------------------------------------------------------------------------
resolve_db_url() {
  if [ -n "${DATABASE_URL:-}" ]; then
    printf '%s' "$DATABASE_URL"
    return 0
  fi

  if [ -n "${SUPABASE_DB_URL:-}" ]; then
    printf '%s' "$SUPABASE_DB_URL"
    return 0
  fi

  if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    local host rest
    host="${SUPABASE_URL#*://}"
    host="${host%%/*}"
    # Supabase exposes the `postgres` superuser on the same host as the API.
    rest="postgres.${host}:5432/postgres?sslmode=require"
    printf 'postgresql://postgres:%s@%s' "$SUPABASE_DB_PASSWORD" "$rest"
    return 0
  fi

  return 1
}

# -----------------------------------------------------------------------------
# Resolve the file list FIRST, so a typo'd test name is an error whether or not
# a database happens to be configured. Resolving this after the "no database"
# skip would make `run-sql-tests.sh rls_user_isolation` silently succeed.
# -----------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  FILES=()
  for name in "$@"; do
    # Accept either "rls_user_isolation" or "rls_user_isolation.test.sql".
    candidate="${name%.test.sql}"
    file="$SQL_DIR/${candidate}.test.sql"
    if [ -f "$file" ]; then
      FILES+=("$file")
    else
      err "No such SQL test: $name (expected $file)"
      exit 1
    fi
  done
else
  mapfile -t FILES < <(find "$SQL_DIR" -maxdepth 1 -name '*.test.sql' | sort)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  log "== SQL tests: no .test.sql files found in $SQL_DIR =="
  exit 0
fi

if ! DB_URL="$(resolve_db_url)"; then
  if [ "${SQL_REQUIRED:-0}" = "1" ]; then
    err "No database configured and SQL_REQUIRED=1."
    err "Set one of: DATABASE_URL, SUPABASE_DB_URL, or (SUPABASE_URL + SUPABASE_DB_PASSWORD)."
    exit 1
  fi
  log "== SQL tests: SKIPPED (no database configured) =="
  log "   ${#FILES[@]} test file(s) were selected but not run."
  log "   Set DATABASE_URL or SUPABASE_DB_URL to run them."
  log "   Use SQL_REQUIRED=1 to make this a hard failure instead."
  exit 0
fi

if ! command -v psql >/dev/null 2>&1; then
  if [ "${SQL_REQUIRED:-0}" = "1" ]; then
    err "psql not found on PATH and SQL_REQUIRED=1."
    exit 1
  fi
  log "== SQL tests: SKIPPED (psql not installed) =="
  log "   ${#FILES[@]} test file(s) were selected but not run."
  log "   Install the PostgreSQL client, then re-run."
  exit 0
fi

# -----------------------------------------------------------------------------
# Run each file. ON_ERROR_STOP makes psql exit non-zero on the first failed
# RAISE EXCEPTION, which is the only thing that makes these scripts able to
# fail at all.
# -----------------------------------------------------------------------------
log "== SQL tests: ${#FILES[@]} file(s) =="
FAILED=()
PASSED=()

for file in "${FILES[@]}"; do
  name="$(basename "$file" .test.sql)"
  log "-- $name"
  if psql "$DB_URL" \
        -v ON_ERROR_STOP=1 \
        -v "__sql_test_name=$name" \
        --quiet \
        -f "$file"; then
    PASSED+=("$name")
  else
    FAILED+=("$name")
  fi
done

log ""
log "-- SQL summary: ${#PASSED[@]} passed, ${#FAILED[@]} failed"
for name in "${FAILED[@]:-}"; do
  [ -n "$name" ] && err "  FAILED: $name"
done

[ "${#FAILED[@]}" -eq 0 ] || exit 1
exit 0