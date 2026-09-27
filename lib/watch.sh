#!/bin/bash
# Detached break timer. Has the app show the panel if the session is still working.
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

# The app draws the panel, and is started if it isn't running.
if ui_deliver "$(ui_json event panel session "$SID" started "$(cat "$STATE/active/$SID" 2>/dev/null)")"; then
  log "panel handed to brb.app for sid=${SID:0:8}"
  exit 0
fi

if legacy_ui; then
  log "showing legacy AppleScript panel for sid=${SID:0:8}"
  exec "$BRB_HOME/lib/panel.sh" "$SID"
fi

rm -f "$STATE/shown/$SID"
log "no app to draw the panel for sid=${SID:0:8} (brb app install)"
exit 0
