#!/usr/bin/env bash
# =============================================================================
# test-all.sh — unified validation entry point (`npm run validate`).
#
# Runs, in parallel:
#   - Backend: eslint, circular-dependency check, syntax check, Jest suite
#   - Flutter: analyze, hardcoded-string scan, widget/unit suite
#   - Duplication scan (jscpd, repo-wide) + analyze_report.js summary
#   - Supabase SQL tests (via scripts/run-sql-tests.sh — skipped with no DB)
#
# PORTABILITY
#   It dispatches through `run()` below, so the same script works on WSL,
#   Git Bash, Linux and macOS.
#
#   Windows paths are converted for docker compose (which needs a native path
#   when invoked from WSL), but only when WSL is actually the environment.
#
# READINESS
#   The mock AI container is polled on /health until it answers or the timeout
#   expires, instead of a blind `sleep 5` that is either flaky (slow CI) or
#   wasted time (fast machines).
#
# LOGS
#   Logs go to Backend/test/logs/ (git-ignored). On success they are removed; on failure
#   they are preserved and printed. Set KEEP_LOGS=1 to always keep them.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.test.yml"
MOCK_AI_HEALTH_URL="${MOCK_AI_HEALTH_URL:-http://127.0.0.1:11434/health}"
MOCK_AI_TIMEOUT_SEC="${MOCK_AI_TIMEOUT_SEC:-60}"

# -----------------------------------------------------------------------------
# Environment detection
# -----------------------------------------------------------------------------
IS_WSL=0
if [ -r /proc/version ] && grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
  IS_WSL=1
fi

# Native (Windows) path for the compose file, but only where needed.
COMPOSE_ARG="$COMPOSE_FILE"
if [ "$IS_WSL" = "1" ] && command -v wslpath >/dev/null 2>&1; then
  COMPOSE_ARG="$(wslpath -w "$COMPOSE_FILE")"
fi

# -----------------------------------------------------------------------------
# run() — invoke a command, transparently handling the Windows/WSL case.
#   `run npm run lint`  and  `run flutter test`  both work everywhere.
# -----------------------------------------------------------------------------
run() {
  if [ "$IS_WSL" = "1" ] && command -v cmd.exe >/dev/null 2>&1; then
    # `//c` avoids MSYS path mangling of the /c switch.
    cmd.exe //c "$@"
  else
    "$@"
  fi
}

log()  { printf '%s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
err()  { printf '  x %s\n' "$*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

compose() {
  run docker compose -f "$COMPOSE_ARG" "$@"
}

# -----------------------------------------------------------------------------
# Teardown + logging
# -----------------------------------------------------------------------------
MOCK_AI_STARTED=0
cleanup() {
  if [ "$MOCK_AI_STARTED" = "1" ]; then
    compose down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

export ENV=test
export NODE_ENV=test

LOG_DIR="$ROOT_DIR/Backend/test/logs"
BACKEND_LOG="$LOG_DIR/backend.log"
FLUTTER_LOG="$LOG_DIR/flutter.log"
DUPLICATION_LOG="$LOG_DIR/duplication.log"
SQL_LOG="$LOG_DIR/supabase.log"

# -----------------------------------------------------------------------------
# Mock AI: start it, then WAIT FOR READINESS (no fixed sleep).
# -----------------------------------------------------------------------------
start_mock_ai() {
  if ! has docker; then
    warn "docker not found — mock AI will not be started."
    warn "Tests that need the AI endpoint will fall back to their local stubs."
    return 0
  fi

  if ! compose up -d mock-ai; then
    warn "Could not start the mock AI container; continuing without it."
    return 0
  fi
  MOCK_AI_STARTED=1

  log "Waiting for Mock AI readiness at $MOCK_AI_HEALTH_URL ..."
  local deadline=$(( $(date +%s) + MOCK_AI_TIMEOUT_SEC ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if has curl && curl -fsS --max-time 2 "$MOCK_AI_HEALTH_URL" >/dev/null 2>&1; then
      log "Mock AI is ready."
      return 0
    fi
    # Fallback for environments without curl: a TCP connect is enough to know
    # the listener is up, since /health is served by the same process.
    if ! has curl && has bash && (exec 3<>"/dev/tcp/127.0.0.1/11434") 2>/dev/null; then
      exec 3>&- 2>/dev/null || true
      log "Mock AI is ready (TCP probe)."
      return 0
    fi
    sleep 1
  done

  warn "Mock AI did not become ready within ${MOCK_AI_TIMEOUT_SEC}s; continuing."
  return 0
}

mkdir -p "$LOG_DIR"
start_mock_ai

# -----------------------------------------------------------------------------
# Code generation
# -----------------------------------------------------------------------------
log "------------------------------------------------"
log "Generating imports..."
if ! (cd "$ROOT_DIR/Flutter" && run dart tool/generate_imports.dart); then
  err "Frontend import generation failed."
  exit 1
fi
if ! (cd "$ROOT_DIR/Backend" && run node tool/generate_imports.js); then
  err "Backend import generation failed."
  exit 1
fi

log "------------------------------------------------"
log "Starting analysis, tests and duplication check in parallel..."
log "------------------------------------------------"

# -----------------------------------------------------------------------------
# Backend
# -----------------------------------------------------------------------------
(
  cd "$ROOT_DIR/Backend" || exit 1
  {
    echo "--- PHASE 0: ESLint Check (Backend, incl. Backend/test) ---"
    run npm run lint && echo "OK: Lint check passed." || { echo "X: Lint check failed."; exit 1; }

    echo ""
    echo "--- PHASE 0.5: Circular Dependency Check ---"
    run npm run madge:circular && echo "OK: No circular dependencies." || { echo "X: Circular dependency found."; exit 1; }

    echo ""
    echo "--- PHASE 1: Node Syntax Check ---"
    run npm run check && echo "OK: Syntax check passed." || { echo "X: Syntax check failed."; exit 1; }

    echo ""
    echo "--- PHASE 2: Backend Tests ---"
    # File-by-file so a failure names the suite and discovery stays explicit.
    shopt -s nullglob
    files=(test/*.test.js)
    shopt -u nullglob
    if [ "${#files[@]}" -eq 0 ]; then
      echo "X: no backend test files found in Backend/test/"
      exit 1
    fi
    for f in "${files[@]}"; do
      echo "Running $f..."
      run npx jest --runInBand "$f" || { echo "X: Test $f failed."; exit 1; }
    done
  } > "$BACKEND_LOG" 2>&1
) &
BACKEND_PID=$!

# -----------------------------------------------------------------------------
# Duplication scan
# -----------------------------------------------------------------------------
(
  cd "$ROOT_DIR" || exit 1
  echo "--- PHASE 1: Duplication Check (Global) ---"
  run npm run scan:duplicates && echo "OK: duplication checks passed." \
    || { echo "X: duplication check failed. Fix clones or adjust thresholds."; exit 1; }
  # Summarise the JSON report jscpd just wrote, so the worst offenders are in
  # the log instead of having to re-run the scan by hand.
  echo ""
  echo "--- PHASE 1.5: Duplication Report Summary ---"
  run node scripts/analyze_report.js || { echo "X: could not summarise the duplication report."; exit 1; }
) > "$DUPLICATION_LOG" 2>&1 &
DUPLICATION_PID=$!

# -----------------------------------------------------------------------------
# Flutter
# -----------------------------------------------------------------------------
(
  cd "$ROOT_DIR/Flutter" || exit 1
  {
    echo "--- PHASE 1: Flutter Analyze ---"
    run flutter analyze && echo "OK: static analysis passed." || { echo "X: static analysis failed."; exit 1; }

    echo ""
    echo "--- PHASE 1.5: Hardcoded String Check ---"
    # `[[:space:]]` instead of `\s`: GNU-specific, breaks on BSD/macOS grep.
    HARDCODED=$(grep -rnE "(title|subtitle|hintText):[[:space:]]*'[A-Za-z]" lib/features/ \
      --include="*.dart" 2>/dev/null \
      | grep -v "context\.loc\." \
      | grep -v "AppLocalizations\." || true)
    if [ -n "$HARDCODED" ]; then
      echo "X: hardcoded UI strings that should use context.loc:"
      echo "$HARDCODED"
      exit 1
    fi
    echo "OK: no hardcoded UI strings found."

    echo ""
    echo "--- PHASE 2: Flutter Tests ---"
    shopt -s nullglob
    files=(test/*_test.dart)
    shopt -u nullglob
    if [ "${#files[@]}" -eq 0 ]; then
      echo "X: no Flutter test files found in test/"
      exit 1
    fi
    for f in "${files[@]}"; do
      echo "Running $f..."
      run flutter test "$f" || { echo "X: Test $f failed."; exit 1; }
    done
  } > "$FLUTTER_LOG" 2>&1
) &
FLUTTER_PID=$!

# -----------------------------------------------------------------------------
# Supabase SQL tests (skips cleanly when no database is configured)
# -----------------------------------------------------------------------------
(
  bash "$SCRIPT_DIR/run-sql-tests.sh"
) > "$SQL_LOG" 2>&1 &
SQL_PID=$!

# -----------------------------------------------------------------------------
# Collect results
# -----------------------------------------------------------------------------
wait "$BACKEND_PID";     BACKEND_EXIT=$?
wait "$FLUTTER_PID";     FLUTTER_EXIT=$?
wait "$DUPLICATION_PID"; DUPLICATION_EXIT=$?
wait "$SQL_PID";         SQL_EXIT=$?

report() {
  local label="$1" code="$2" logfile="$3" desc="$4"
  if [ "$code" -eq 0 ]; then
    echo "OK $label: PASSED ($desc)"
  else
    echo "X $label: FAILED (exit $code)"
    echo "--- $label log snippet ---"
    if [ -f "$logfile" ]; then
      tail -n 100 "$logfile"
    else
      err "log file not found at $logfile"
    fi
    echo "---------------------------"
  fi
}

echo ""
echo "================================================"
echo "                CHECK SUMMARY                   "
echo "================================================"
report "BACKEND  " "$BACKEND_EXIT"     "$BACKEND_LOG"     "lint, deps, syntax, tests"
report "FLUTTER  " "$FLUTTER_EXIT"     "$FLUTTER_LOG"     "analyze, i18n scan, tests"
report "DUP CHECK" "$DUPLICATION_EXIT" "$DUPLICATION_LOG" "jscpd"
report "SQL      " "$SQL_EXIT"         "$SQL_LOG"         "supabase/test/*.test.sql"

if [ "$BACKEND_EXIT" -eq 0 ] && [ "$FLUTTER_EXIT" -eq 0 ] \
   && [ "$DUPLICATION_EXIT" -eq 0 ] && [ "$SQL_EXIT" -eq 0 ]; then
  echo "================================================"
  if [ "${KEEP_LOGS:-0}" = "1" ]; then
    log "Logs preserved at: $LOG_DIR"
  else
    rm -rf "$LOG_DIR"
  fi
  exit 0
fi

echo "================================================"
warn "Checks failed. Detailed logs preserved at: $LOG_DIR"
exit 1