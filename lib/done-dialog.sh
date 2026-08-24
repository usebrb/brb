#!/bin/bash
# Detached "Claude is done" alert: banner for the record, dialog for the action.
# Runs outside the Stop hook so it can wait for a click past the hook timeout.
BRB_TAG=donedlg
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

msg="$1"; app="$2"
[ -n "$msg" ] || msg="Turn complete."

if is_dry; then
  log "DRY: would show done dialog, return-to='$app', msg='$msg'"
  exit 0
fi

[ -f "$SOUNDS/$SOUND_DONE.aiff" ] && "$AFPLAY" "$SOUNDS/$SOUND_DONE.aiff" >/dev/null 2>&1 &
"$OSA" -e "display notification $(as_str "$msg") with title $(as_str "$TITLE_DONE")" >/dev/null 2>&1

# Nothing recorded to go back to: the banner alone will have to do.
[ -n "$app" ] || { log "no terminal recorded, banner only"; exit 0; }

script="activate
set r to display dialog $(as_str "$msg") with title $(as_str "$TITLE_DONE") buttons {\"Stay\", \"Back to work\"} default button \"Stay\" giving up after 600
if gave up of r is false and button returned of r is \"Back to work\" then
  try
    tell application id $(as_str "$app") to activate
  end try
end if
return button returned of r"

focus=$(anchor_center "$app")   # $app is the owning terminal bundle id
"$OSA" -e "$script" > "$STATE/done.txt" 2>/dev/null &
pid=$!
center_dialog "$pid" "${focus%%,*}" "${focus##*,}"
echo "$pid" > "$STATE/done.pid"
wait "$pid"
[ "$(cat "$STATE/done.pid" 2>/dev/null)" = "$pid" ] && rm -f "$STATE/done.pid"
log "done dialog closed: $(cat "$STATE/done.txt" 2>/dev/null)"
exit 0
