#!/bin/bash
# UserPromptSubmit: mark this session working, arm the break timer.
# The panel and alerts are AppleScript; nothing to do elsewhere.
[ "$(uname)" = Darwin ] || exit 0
BRB_TAG=start
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
is_off && { log "OFF, ignoring"; exit 0; }

prune_stale
eval "$(cat | parse_hook_json)"
[ -n "$HK_SESSION" ] || { log "no session_id in payload"; exit 0; }

kill_done_dialog
date +%s > "$STATE/active/$HK_SESSION"
rm -f "$STATE/shown/$HK_SESSION" "$STATE/left/$HK_SESSION" "$STATE/rearm/$HK_SESSION"

# The terminal that owns this session, from the process tree. Falls back to
# the focused app only if that walk fails.
{ owning_terminal_bundle || frontmost_bundle; } > "$STATE/term/$HK_SESSION" 2>/dev/null

# You just typed here, so the terminal is frontmost and readable right now.
# Later it may be on another Space where its geometry can't be queried.
app_window_center "$(cat "$STATE/term/$HK_SESSION" 2>/dev/null)" > "$STATE/anchor/$HK_SESSION" 2>/dev/null

log "busy sid=${HK_SESSION:0:8} owner=$(cat "$STATE/term/$HK_SESSION" 2>/dev/null) delay=$(current_delay)s"
spawn_detached "$BRB_HOME/lib/watch.sh" "$HK_SESSION"
exit 0
