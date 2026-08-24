#!/bin/bash
# Stop: the turn ended. Take the panel down and, if the panel sent you away,
# call you back.
BRB_TAG=done
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
is_off && { log "OFF, ignoring"; exit 0; }

eval "$(cat | parse_hook_json)"
[ -n "$HK_SESSION" ] || { log "no session_id in payload"; exit 0; }

rm -f "$STATE/active/$HK_SESSION"

was_shown=0; [ -f "$STATE/shown/$HK_SESSION" ] && was_shown=1
was_left=0;  [ -f "$STATE/left/$HK_SESSION" ]  && was_left=1
term=$(cat "$STATE/term/$HK_SESSION" 2>/dev/null)
rm -f "$STATE/shown/$HK_SESSION" "$STATE/term/$HK_SESSION" "$STATE/left/$HK_SESSION"

log "stop sid=${HK_SESSION:0:8} shown=$was_shown left=$was_left owner='$term'"

# The panel is one shared window, so it only comes down when nothing is busy.
if [ -n "$(ls -A "$STATE/active" 2>/dev/null)" ]; then
  log "panel stays: still busy -> $(ls -A "$STATE/active" | cut -c1-8 | tr '\n' ' ')"
else
  kill_panel
fi

# The alert is per-session, and only if the panel actually sent you somewhere.
[ "$was_left" = 1 ] || { log "you never left via the panel -> no ping"; exit 0; }

front=$(frontmost_bundle)
log "frontmost='$front' vs owner='$term'"
same_app "$term" "$front" && { log "you are at the terminal -> no ping"; exit 0; }

msg="$HK_LAST"; [ -n "$msg" ] || msg="Turn complete."
log "PINGING (dialog, return-to='$term'): $msg"
spawn_detached "$BRB_HOME/lib/done-dialog.sh" "$msg" "$term"
exit 0
