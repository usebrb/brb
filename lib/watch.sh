#!/bin/bash
# Detached break timer. Shows the panel if the session is still working.
BRB_TAG=watch
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SID="$1"
[ -n "$SID" ] || exit 0

sleep "$(current_delay)"

is_off && { log "OFF"; exit 0; }
[ -f "$STATE/active/$SID" ] || { log "sid=${SID:0:8} finished before timer, no panel"; exit 0; }

pid=$(cat "$STATE/panel.pid" 2>/dev/null)
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { log "another panel already up"; exit 0; }

is_dry && { log "DRY: would show panel for sid=${SID:0:8}"; exit 0; }
date +%s > "$STATE/shown/$SID"

# The app draws a nicer panel when it is running. Otherwise, AppleScript.
if ui_send "$(ui_json event panel session "$SID" started "$(cat "$STATE/active/$SID" 2>/dev/null)")"; then
  log "panel handed to brb.app for sid=${SID:0:8}"
  exit 0
fi

log "showing panel for sid=${SID:0:8}"
exec "$BRB_HOME/lib/panel.sh" "$SID"
