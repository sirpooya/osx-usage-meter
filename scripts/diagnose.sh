#!/bin/bash
#
# diagnose.sh
#
# Prints everything known about why UsageMeter stopped running.
# Run it right after the app disappears.
#
#   ./scripts/diagnose.sh
#
set -uo pipefail

BUNDLE_ID="in.pooya.usagemeter"
LOG_DIR="$HOME/Library/Application Support/UsageMeter/logs"
HOURS="${1:-24}"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
rule() { printf '%s\n' "----------------------------------------------------------------"; }

# `log show` has no timeout of its own and can run for minutes. Cap it, and say
# so rather than looking hung. Falls back cleanly when perl is unavailable.
LOG_QUERY_TIMEOUT="${LOG_QUERY_TIMEOUT:-45}"
run_log_query() {
    local predicate="$1"
    local out
    if command -v perl >/dev/null 2>&1; then
        out="$(perl -e 'alarm shift; exec @ARGV' "$LOG_QUERY_TIMEOUT" \
            log show --last "${HOURS}h" --style compact --predicate "$predicate" 2>/dev/null | tail -20)"
    else
        out="$(log show --last "${HOURS}h" --style compact --predicate "$predicate" 2>/dev/null | tail -20)"
    fi
    if [[ -z "$out" ]]; then
        echo "(nothing found, or the query hit the ${LOG_QUERY_TIMEOUT}s limit)"
    else
        printf '%s\n' "$out"
    fi
}

bold "UsageMeter diagnostics"
printf 'generated %s, looking back %sh\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$HOURS"
rule

# 1. Is it even running? A menu bar app can be alive with no visible icon,
#    which is a Control Center problem and not a crash at all.
bold "1. Process state"
if pgrep -x UsageMeter >/dev/null 2>&1; then
    ps -o pid,etime,rss,%cpu,command -p "$(pgrep -x UsageMeter | head -1)"
    echo "Running. If you cannot see the menu bar icon, the process is fine and"
    echo "Control Center is hiding it. See the menubar-fix skill."
else
    echo "Not running."
fi
rule

# 2. The verdict from the app's own sentinel. This is the primary answer.
bold "2. Session history (start / clean / CRASHED / KILLED)"
if [[ -f "$LOG_DIR/sessions.log" ]]; then
    tail -40 "$LOG_DIR/sessions.log"
    echo
    echo "Counts:"
    printf '  clean exits : %s\n' "$(grep -c 'exit clean'      "$LOG_DIR/sessions.log" 2>/dev/null || echo 0)"
    printf '  crashed     : %s\n' "$(grep -c 'previous CRASHED' "$LOG_DIR/sessions.log" 2>/dev/null || echo 0)"
    printf '  killed      : %s\n' "$(grep -c 'previous KILLED'  "$LOG_DIR/sessions.log" 2>/dev/null || echo 0)"
else
    echo "No session ledger yet at $LOG_DIR/sessions.log"
    echo "It appears the first time the instrumented build launches."
fi
rule

# 3. Backtrace, when the app actually crashed.
bold "3. Last crash marker (app captured)"
if [[ -f "$LOG_DIR/last-crash.txt" ]]; then
    cat "$LOG_DIR/last-crash.txt"
else
    echo "None. The app has not caught a crash."
fi
rule

# 4. macOS crash reports. Their absence is itself evidence: no .ips file plus
#    a KILLED verdict means the process was terminated from outside.
bold "4. macOS crash reports"
FOUND=0
for dir in "$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r report; do
        [[ -n "$report" ]] || continue
        FOUND=1
        echo "--- $report"
        head -20 "$report"
    done < <(find "$dir" -maxdepth 1 \( -iname "UsageMeter*" -o -iname "Usage4Claude*" \) -mtime -7 2>/dev/null)
done
if [[ "$FOUND" -eq 0 ]]; then
    echo "No crash reports in the last 7 days."
    echo "If a session is marked KILLED above, that combination means the app did"
    echo "NOT crash. Something outside stopped it: memory pressure, force quit,"
    echo "logout, or a Sparkle update relaunch."
fi
rule

# 5. Jetsam. The usual culprit for a silently killed background agent.
bold "5. Memory pressure and jetsam"
# Scoped to the process name so the query stays fast. An unscoped
# system-wide log show over 24h can take minutes.
run_log_query 'eventMessage CONTAINS "jetsam" AND eventMessage CONTAINS[c] "UsageMeter"' 
echo "(no output above means no jetsam kill was recorded for this app)"
rule

# 6. Control Center blocking. The specific macOS 26 failure where the icon
#    vanishes and the app looks like it quit.
bold "6. Control Center status item blocking"
run_log_query '(eventMessage CONTAINS "blocked list" OR eventMessage CONTAINS "Moving host") AND eventMessage CONTAINS[c] "usagemeter"' 
echo "(no output above means the status item was not blocked)"
rule

# 7. The app's own recent errors, which bound the time of death.
bold "7. Recent app errors and warnings"
LATEST_LOG="$(find "$LOG_DIR" -maxdepth 1 -name "usagemeter_*.log" -type f 2>/dev/null | sort | tail -1)"
if [[ -n "$LATEST_LOG" ]]; then
    echo "from $LATEST_LOG"
    grep -E "\[(ERROR|WARNING)\]" "$LATEST_LOG" 2>/dev/null | tail -30
    echo
    echo "Last 15 lines of any level, which is what the app was doing at the end:"
    tail -15 "$LATEST_LOG"
else
    echo "No app log files yet in $LOG_DIR"
fi
rule

# 8. Unified log for the subsystem, catching anything the file logger missed.
bold "8. Unified log for $BUNDLE_ID"
run_log_query "subsystem == \"$BUNDLE_ID\""
echo "(empty is normal if the app has not run since the last reboot)"
rule

bold "How to read this"
cat <<'GUIDE'
  CRASHED + a backtrace in section 3    -> the app's own bug, fix the frame
  KILLED  + jetsam in section 5         -> memory. Look for a leak
  KILLED  + blocking in section 6       -> Control Center, not a crash
  KILLED  + nothing else                -> force quit, logout, or update relaunch
  Running + no visible icon             -> Control Center, use the menubar-fix skill
GUIDE
