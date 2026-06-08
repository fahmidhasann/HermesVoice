#!/bin/bash
#
# auto-rebuild.sh — Claude Code "Stop" hook for HermesVoice.
#
# WHY THIS EXISTS
#   The app you actually run is the bundle at build/HermesVoice.app. Plain
#   `swift build` only updates .build/ — it does NOT touch that bundle. So a
#   code change could compile yet never reach the app you're looking at (the
#   exact bug we just hit: a fix that built but ran on a stale bundle).
#
#   This hook runs every time the AI finishes a turn. If any Swift source
#   changed, it rebuilds the bundle (via build-app.sh) and relaunches the app
#   so what's on screen always matches the latest code.
#
#   It is deliberately cheap on turns that change nothing: a quick file-time
#   check short-circuits before any compile, so non-coding turns cost ~nothing.

# --- locate the project (this script lives in <project>/.claude/hooks/) -------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

# Ensure the Swift toolchain is reachable even under a minimal hook environment.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

LOG="/tmp/hermesvoice-autobuild.log"
STAMP=".build/.hv-autobuild-stamp"   # its mtime = time of last successful bundle
APP="$PROJECT_DIR/build/HermesVoice.app"
APP_MATCH="HermesVoice.app/Contents/MacOS/HermesVoice"

# --- 1. Loop guard -----------------------------------------------------------
# If this Stop is itself the result of a previous Stop hook asking Claude to
# continue, do nothing. Prevents any possibility of a stop/continue loop.
INPUT="$(cat)"
case "$INPUT" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# --- 2. Did any Swift source change since the last successful bundle? ---------
# No stamp yet  -> first run, fall through and build.
# Stamp exists  -> short-circuit unless something under Sources/ (or
#                  Package.swift) is newer than it.
if [ -f "$STAMP" ]; then
  changed="$(find Sources -name '*.swift' -newer "$STAMP" -print -quit 2>/dev/null)"
  if [ -z "$changed" ] && [ ! Package.swift -nt "$STAMP" ]; then
    exit 0
  fi
fi

# --- 3. Rebuild the bundle (all build noise to the log; stdout = JSON only) ---
echo "===== $(date) =====" >>"$LOG" 2>&1
if ! ./build-app.sh >>"$LOG" 2>&1; then
  # Build broke: leave the running app untouched, but make the staleness loud.
  printf '{"systemMessage":"⚠️ HermesVoice did NOT rebuild — the running app still has your PREVIOUS code because the build failed. Ask me to fix it (build log: %s).","suppressOutput":true}\n' "$LOG"
  exit 0
fi

# Success — record this moment so future turns can short-circuit.
touch "$STAMP"
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo '?')"

# --- 4. Relaunch only if the app is currently running ------------------------
# (Don't pop the app open uninvited; just refresh it if you're using it.)
if pgrep -f "$APP_MATCH" >/dev/null 2>&1; then
  pkill -f "$APP_MATCH" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do          # wait briefly for a clean exit
    pgrep -f "$APP_MATCH" >/dev/null 2>&1 || break
    sleep 0.2
  done
  open "$APP" >>"$LOG" 2>&1
  printf '{"systemMessage":"✅ HermesVoice rebuilt (build %s) and relaunched — the running app now matches your latest code.","suppressOutput":true}\n' "$BUILD_NUM"
else
  printf '{"systemMessage":"✅ HermesVoice rebuilt (build %s). It was not running, so I left it closed; it will have your latest code next time you open it.","suppressOutput":true}\n' "$BUILD_NUM"
fi

exit 0
