#!/bin/bash
# UserPromptSubmit: mark this session working, arm the break timer.
BRB_TAG=start
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
is_off && { log "OFF, ignoring"; exit 0; }

eval "$(cat | parse_hook_json)"
[ -n "$HK_SESSION" ] || { log "no session_id in payload"; exit 0; }

kill_done_dialog
date +%s > "$STATE/active/$HK_SESSION"
rm -f "$STATE/shown/$HK_SESSION" "$STATE/left/$HK_SESSION"

# The terminal that owns this session, from the process tree. Falls back to
# the focused app only if that walk fails.
{ owning_terminal_bundle || frontmost_bundle; } > "$STATE/term/$HK_SESSION" 2>/dev/null

log "busy sid=${HK_SESSION:0:8} owner=$(cat "$STATE/term/$HK_SESSION" 2>/dev/null) delay=$(current_delay)s"
spawn_detached "$BRB_HOME/lib/watch.sh" "$HK_SESSION"
exit 0
