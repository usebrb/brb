#!/bin/bash
# Stop: the turn ended. Take the panel down and, if the panel sent you away,
# call you back.
# The panel and alerts are AppleScript; nothing to do elsewhere.
[ "$(uname)" = Darwin ] || exit 0
BRB_TAG=done
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
is_off && { log "OFF, ignoring"; exit 0; }

prune_stale
eval "$(cat | parse_hook_json)"
[ -n "$HK_SESSION" ] || { log "no session_id in payload"; exit 0; }

rm -f "$STATE/active/$HK_SESSION"

was_shown=0; [ -f "$STATE/shown/$HK_SESSION" ] && was_shown=1
was_left=0;  [ -f "$STATE/left/$HK_SESSION" ]  && was_left=1
term=$(cat "$STATE/term/$HK_SESSION" 2>/dev/null)
anchor=$(cat "$STATE/anchor/$HK_SESSION" 2>/dev/null)
rm -f "$STATE/shown/$HK_SESSION" "$STATE/term/$HK_SESSION" "$STATE/left/$HK_SESSION" "$STATE/anchor/$HK_SESSION" "$STATE/rearm/$HK_SESSION"

log "stop sid=${HK_SESSION:0:8} shown=$was_shown left=$was_left owner='$term'"

# The panel is one shared window, so it only comes down when nothing is busy.
if [ -n "$(ls -A "$STATE/active" 2>/dev/null)" ]; then
  log "panel stays: still busy -> $(ls -A "$STATE/active" | cut -c1-8 | tr '\n' ' ')"
  panel_action=keep
else
  kill_panel
  panel_action=close
fi

# Whatever happens next, the app stops counting this session.
ui_clear() {
  ui_send "$(ui_json event stop session "$HK_SESSION" panel "$panel_action")" >/dev/null 2>&1
  return 0
}

# The alert is per-session, and only if the panel actually sent you somewhere.
[ "$was_left" = 1 ] || { ui_clear; log "you never left via the panel -> no ping"; exit 0; }

# You asked to be taken away, so you get told when it's done. Sampling focus at
# the exact instant Stop fires made this a coin flip.
if [ "$REQUIRE_AWAY" = 1 ]; then
  front=$(frontmost_bundle)
  log "frontmost='$front' vs owner='$term'"
  same_app "$term" "$front" && { ui_clear; log "still at the terminal -> no ping"; exit 0; }
fi

msg="$HK_LAST"; [ -n "$msg" ] || msg="Turn complete."

# The app's callback card, if it is running. Otherwise the AppleScript dialog.
if ui_send "$(ui_json event done session "$HK_SESSION" message "$msg" \
              owner "$term" cwd "$HK_CWD" panel "$panel_action")"; then
  log "PINGING (brb.app, return-to='$term'): $msg"
  exit 0
fi

log "PINGING (dialog, return-to='$term'): $msg"
spawn_detached "$BRB_HOME/lib/done-dialog.sh" "$msg" "$term" "$anchor"
exit 0
