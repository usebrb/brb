#!/bin/bash
# Notification: Claude wants something from you.
# The panel and alerts are AppleScript; nothing to do elsewhere.
[ "$(uname)" = Darwin ] || exit 0
BRB_TAG=attention
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
is_off && { log "OFF, ignoring"; exit 0; }

eval "$(cat | parse_hook_json)"

kill_panel
log "notification type=$HK_NTYPE sid=${HK_SESSION:0:8}"

term=""
[ -n "$HK_SESSION" ] && term=$(cat "$STATE/term/$HK_SESSION" 2>/dev/null)

# idle_prompt fires when a session finishes and waits - the same moment as Stop.
# Hold it to the same rule as the done alert. permission_prompt and
# agent_needs_input stay ungated: Claude is BLOCKED on you there, which matters
# whether or not you took a break.
if [ "$HK_NTYPE" = "idle_prompt" ] && [ ! -f "$STATE/left/$HK_SESSION" ]; then
  log "idle but you never left via the panel -> no ping"
  exit 0
fi

front=$(frontmost_bundle)
if ! same_app "$term" "$front"; then
  case "$HK_NTYPE" in
    permission_prompt)      msg="Waiting on a permission decision." ;;
    agent_needs_input)      msg="An agent needs your input." ;;
    elicitation_dialog)     msg="Claude is asking you a question." ;;
    elicitation_url_dialog) msg="Claude needs you to open a link." ;;
    idle_prompt)       msg="Claude has gone idle." ;;
    *)                 msg="Claude needs your attention." ;;
  esac
  log "PINGING type=$HK_NTYPE: $msg"
  notify "$TITLE_ATTENTION" "$msg" "$SOUND_ATTENTION"
fi

# Re-arm once: after you answer, the panel can come back if you wander off
# again. Only once per turn - a turn with several permission prompts used to
# reopen the panel after every one of them.
if [ -n "$HK_SESSION" ] && [ -f "$STATE/active/$HK_SESSION" ]; then
  if [ -f "$STATE/rearm/$HK_SESSION" ]; then
    log "already re-armed this turn -> not reopening the panel"
  else
    date +%s > "$STATE/rearm/$HK_SESSION"
    rm -f "$STATE/shown/$HK_SESSION"
    spawn_detached "$BRB_HOME/lib/watch.sh" "$HK_SESSION"
    log "re-armed the panel (once per turn)"
  fi
fi
exit 0
