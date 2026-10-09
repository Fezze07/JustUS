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
#   Runs parallel checks across Backend, Flutter, Duplication, and SQL tests.
#
# LOGS
#   Logs go to Backend/test/logs/ (git-ignored). On success they are removed; on failure
#   they are preserved and printed. Set KEEP_LOGS=1 to always keep them.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.test.yml"

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

export ENV=test
export NODE_ENV=test

LOG_DIR="$ROOT_DIR/Backend/test/logs"
BACKEND_LOG="$LOG_DIR/backend.log"
FLUTTER_LOG="$LOG_DIR/flutter.log"
DUPLICATION_LOG="$LOG_DIR/duplication.log"
SQL_LOG="$LOG_DIR/supabase.log"

mkdir -p "$LOG_DIR"

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
    # Hardcoded UI strings that should be routed through loc.
    #  - Matches a UI-bearing named parameter followed by a string literal,
    #    in single OR double quotes.
    #  - Matches a bare Text('literal') / Text("literal") constructor.
    # message:/description: are deliberately NOT scanned: they also feed
    # technical error payloads (AppError/GenericError/NetworkError + logging),
    # which are code-level strings; production UI shows localized text through
    # ErrorCodes.userMessage(code, ctx.loc), so those must not go into loc.
    # `[[:space:]]` instead of `\s`: GNU-specific, breaks on BSD/macOS grep.
    HARDCODED=$(grep -rnE \
      "(title|subtitle|hintText|labelText|label|tooltip|semanticLabel|helperText|errorText|counterText|content|text|heading|actionLabel|buttonText|prefixText|suffixText):[[:space:]]*['\"][A-Za-z]|Text\([[:space:]]*['\"][A-Za-z]" \
      lib/features/ --include="*.dart" 2>/dev/null \
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