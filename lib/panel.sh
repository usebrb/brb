#!/bin/bash
# The break panel: a native list whose first row adjusts its own timer.
BRB_TAG=panel
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SID="$1"
# Anchor every dialog this panel draws to the terminal that owns the session.
BRB_ANCHOR=$(cat "$STATE/term/$SID" 2>/dev/null)
export BRB_ANCHOR
SEP="──────────────────────────────"
SEP2="───────────────────────────────"   # one shorter, so the two rows differ
ADD_ROW="➕  Add your own…"

change_delay() {
  local cur secs val script
  cur=$(current_delay)
  while :; do
    script="activate
set r to display dialog $(as_str "Show the break panel after how long?

Accepts: 10, 45s, 2m, 1m30s") default answer $(as_str "$(fmt_delay "$cur")") with title \"Break timer\" buttons {\"Cancel\", \"Save\"} default button \"Save\"
return text returned of r"
    osa_tracked "$STATE/dlg.txt" "$script" || return 1
    val=$(cat "$STATE/dlg.txt" 2>/dev/null)
    if secs=$(parse_delay "$val"); then
      echo "$secs" > "$STATE/delay"
      log "break timer set to ${secs}s"
      "$OSA" -e "activate" -e "display dialog $(as_str "Break timer set to $(fmt_delay "$secs").

Takes effect from the next turn — this one keeps its original wait.") buttons {\"OK\"} default button \"OK\" with title \"Break timer\"" >/dev/null 2>&1
      return 0
    fi
    "$OSA" -e "activate" -e "display dialog $(as_str "\"$val\" isn't a duration I can read. Try 10, 45s, 2m, or 1m30s (minimum 3s).") buttons {\"OK\"} default button \"OK\" with title \"Break timer\" with icon caution" >/dev/null 2>&1
  done
}

show_note() {
  "$OSA" -e "activate" -e "display dialog $(as_str "$1") buttons {\"OK\"} default button \"OK\" with title \"Break\"" >/dev/null 2>&1
}

while :; do
  is_off && exit 0
  # Claude finished while the panel sat open (or mid-edit): stand down.
  [ -n "$SID" ] && { [ -f "$STATE/active/$SID" ] || exit 0; }

  delay=$(current_delay)
  timer_row="⏱  Break timer: $(fmt_delay "$delay") — change…"

  items=("$timer_row" "$SEP")
  labels=(); targets=()
  src=$(items_file)
  if [ -f "$src" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      case "$line" in *'|'*) ;; *) continue ;; esac
      lbl="${line%%|*}"; tgt="${line#*|}"
      items+=("$lbl"); labels+=("$lbl"); targets+=("$tgt")
    done < "$src"
  fi

  items+=("$SEP2" "$ADD_ROW")

  lst=""
  for it in "${items[@]}"; do
    [ -n "$lst" ] && lst="$lst, "
    lst="$lst$(as_str "$it")"
  done

  busy=""
  if [ -n "$SID" ] && [ -f "$STATE/active/$SID" ]; then
    started=$(cat "$STATE/active/$SID" 2>/dev/null)
    [ -n "$started" ] && busy="Busy $(fmt_delay $(( $(date +%s) - started ))) · "
  fi

  script="activate
set c to choose from list {$lst} with title $(as_str "$PANEL_TITLE") with prompt $(as_str "${busy}break timer $(fmt_delay "$delay")") OK button name \"Go\" cancel button name \"Stay\"
if c is false then
  return \"__stay__\"
else
  return item 1 of c
end if"

  osa_tracked "$STATE/choice.txt" "$script" || { log "panel closed from outside (Claude finished)"; exit 0; }
  choice=$(cat "$STATE/choice.txt" 2>/dev/null)
  log "picked: $choice"

  case "$choice" in
    ''|'__stay__') exit 0 ;;
    "$SEP"|"$SEP2") continue ;;
    "$timer_row")  change_delay; continue ;;
    "$ADD_ROW")
      "$OPEN" "$CONTRIB_URL"
      [ -n "$SID" ] && date +%s > "$STATE/left/$SID"
      sleep 0.7
      activate_bundle "$(default_browser_id)"
      log "opened CONTRIBUTING.md"
      exit 0
      ;;
  esac

  target=""; i=0
  while [ $i -lt ${#labels[@]} ]; do
    [ "${labels[$i]}" = "$choice" ] && { target="${targets[$i]}"; break; }
    i=$((i + 1))
  done

  case "$target" in
    note:*)
      # A note isn't a departure: show it, then bring the panel back.
      show_note "${target#note:}"
      continue
      ;;
    http://*|https://*)
      "$OPEN" "$target"
      [ -n "$SID" ] && date +%s > "$STATE/left/$SID"
      bid=$(default_browser_id)
      sleep 0.7
      activate_bundle "$bid"
      log "opened $target -> foregrounded '${bid:-?}'"
      ;;
    *://*)
      "$OPEN" "$target"
      [ -n "$SID" ] && date +%s > "$STATE/left/$SID"
      log "opened $target"
      ;;
  esac
  exit 0
done
