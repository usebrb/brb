#!/bin/bash
# End-to-end tests for the hook -> app wiring, the banner fallback when the app
# is not installed, and the deprecated AppleScript UI behind LEGACY_UI=1.
#
#   test/hooks.test.sh
#
# Everything runs against a throwaway BRB_CONF, so your real config, items and
# log are never touched. macOS only.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$REPO/app/dist/brb.app/Contents/MacOS/brb"
PASS=0; FAIL=0

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
note() { printf '\n\033[1m%s\033[0m\n' "$1"; }

assert_ok()      { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "$2"; fi; }
assert_fails()   { if eval "$2" >/dev/null 2>&1; then bad "$1" "expected failure: $2"; else ok "$1"; fi; }
assert_log()     { if grep -qF "$2" "$SANDBOX/state/brb.log" 2>/dev/null; then ok "$3"; else bad "$3" "no '$2' in the log"; fi; }
assert_no_log()  { if grep -qF "$2" "$SANDBOX/state/brb.log" 2>/dev/null; then bad "$3" "unexpected '$2' in the log"; else ok "$3"; fi; }
assert_file()    { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing $2"; fi; }
assert_no_file() { if [ -e "$2" ]; then bad "$1" "unexpected $2"; else ok "$1"; fi; }

[ "$(uname)" = Darwin ] || { echo "macOS only"; exit 0; }

SANDBOX=$(mktemp -d /tmp/brb-test.XXXXXX)
export BRB_CONF="$SANDBOX"
export BRB_HOME="$REPO"
export BRB_QUIET=1          # a test run must not ring the machine it runs on
cleanup() {
  if [ -n "${APP_PID:-}" ]; then
    kill "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null   # keeps job control from printing "Terminated"
  fi
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

mkdir -p "$SANDBOX/state"
printf '3\n' > "$SANDBOX/state/delay"          # the floor, so waits stay short
cat > "$SANDBOX/items.txt" <<'ITEMS'
🐦 X|https://x.com
💧 Water|note:Refill.
ITEMS

hook() { printf '%s' "$2" | "$REPO/hooks/$1"; }
fresh_log() { : > "$SANDBOX/state/brb.log"; }

echo "brb hook tests   sandbox: $SANDBOX"

# --- 1. no app: the shell path has to carry everything ----------------------

note "with no app running"
. "$REPO/lib/common.sh"

assert_fails "ui_up reports no app when the socket is missing" "ui_up"
assert_fails "ui_send refuses without a socket"                "ui_send '{\"event\":\"ping\"}'"
assert_ok    "ui_json builds valid JSON" \
  "[ \"\$(ui_json event panel session s1 | $PY -c 'import json,sys;d=json.load(sys.stdin);print(d[\"session\"])')\" = s1 ]"

fresh_log
BRB_DRY=1 hook on-start.sh '{"session_id":"t1","cwd":"/tmp/demo"}'
assert_file "UserPromptSubmit marks the session working" "$SANDBOX/state/active/t1"
assert_log  "" "busy sid=t1" "the start hook logs the turn"

fresh_log
date +%s > "$SANDBOX/state/left/t1"
BRB_DRY=1 BRB_FAKE_FRONT="com.example.Browser" hook on-done.sh \
  '{"session_id":"t1","last_assistant_message":"All done."}'
assert_log    "" "PINGING (banner" "Stop falls back to a banner"
assert_no_log "" "PINGING (legacy dialog" "and never to the old AppleScript dialog"

fresh_log
BRB_DRY=1 hook on-start.sh '{"session_id":"t1","cwd":"/tmp/demo"}'
date +%s > "$SANDBOX/state/left/t1"
BRB_LEGACY_UI=1 BRB_DRY=1 BRB_FAKE_FRONT="com.example.Browser" hook on-done.sh \
  '{"session_id":"t1","last_assistant_message":"All done."}'
assert_log "" "PINGING (legacy dialog" "LEGACY_UI=1 brings the old dialog back"

fresh_log
BRB_DRY=1 hook on-start.sh '{"session_id":"t2","cwd":"/tmp/demo"}'
BRB_DRY=1 "$REPO/lib/watch.sh" t2
assert_log "" "DRY: would show panel" "the watcher would show the panel"

fresh_log
BRB_UI=0 hook on-start.sh '{"session_id":"t2b","cwd":"/tmp/demo"}'
BRB_UI=0 "$REPO/lib/watch.sh" t2b
assert_log     "" "no app to draw the panel" "with no app, the watcher draws nothing"
assert_no_log  "" "legacy AppleScript panel" "not even the old AppleScript panel"
assert_no_file "and does not count the panel as shown" "$SANDBOX/state/shown/t2b"
rm -f "$SANDBOX"/state/active/* "$SANDBOX"/state/left/* "$SANDBOX"/state/shown/*

# --- 2. app running: it takes over, and the shell draws nothing -------------

note "with the app running"
if [ ! -x "$APP_BIN" ]; then
  echo "  building the app first…"
  "$REPO/app/build.sh" >/dev/null || { bad "app builds" "app/build.sh failed"; exit 1; }
fi

# Headless: the app answers and logs as usual but draws nothing, so a test run
# doesn't flash panels and callback cards on the screen of whoever runs it.
BRB_CONF="$SANDBOX" BRB_QUIET=1 BRB_HEADLESS=1 "$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$SANDBOX/state/ui.sock" ] && break; sleep 0.3; done
assert_file "the app opens its socket" "$SANDBOX/state/ui.sock"

assert_file "the app leaves a pointer to its own bundle" "$SANDBOX/state/ui.app"
assert_ok   "and the client resolves through that pointer" \
  "[ \"\$(ui_client)\" = \"\$(cat '$SANDBOX/state/ui.app')/Contents/MacOS/brb\" ]"

assert_ok "ui_up finds the app"                    "ui_up"
assert_ok "an unknown event is refused, not obeyed" \
  "! ui_send '{\"event\":\"nonsense\"}'"
assert_ok "malformed JSON is refused"              "! ui_send 'not json'"

fresh_log
hook on-start.sh '{"session_id":"t3","cwd":"/tmp/brbdemo","last_assistant_message":""}'
assert_file "the session is still marked working" "$SANDBOX/state/active/t3"

fresh_log
"$REPO/lib/watch.sh" t3
assert_log    "" "panel handed to brb.app" "the watcher hands the panel to the app"
assert_no_log "" "DRY: would show panel"   "and does not also draw the AppleScript one"

# A turn that ends without you having left: no callback, either way.
fresh_log
hook on-done.sh '{"session_id":"t3","last_assistant_message":"Finished."}'
assert_log    "" "you never left via the panel" "no departure means no callback"
assert_no_log "" "PINGING"                      "and nothing is pinged"

# A turn that ends after you left: the app draws the card, not osascript.
fresh_log
hook on-start.sh '{"session_id":"t4","cwd":"/tmp/brbdemo"}'
date +%s > "$SANDBOX/state/left/t4"
hook on-done.sh '{"session_id":"t4","last_assistant_message":"Wired the app up."}'
assert_log    "" "PINGING (brb.app" "the app draws the callback"
assert_no_log "" "PINGING (legacy dialog" "and the AppleScript dialog stays out of it"

fresh_log
BRB_FAKE_FRONT="com.example.Browser" hook on-attention.sh '{"session_id":"t4","notification_type":"permission_prompt"}'
assert_log "" "PINGING type=permission_prompt" "attention pings still fire"
assert_log "" "quiet: would notify" "and the banner is suppressed under BRB_QUIET"

# `brb reset` clears the shell's markers; the app has to let go of the same
# sessions, or the menu bar counts a turn that ended long ago.
fresh_log
hook on-start.sh '{"session_id":"r1","cwd":"/tmp/one"}'
hook on-start.sh '{"session_id":"r2","cwd":"/tmp/two"}'
if ui_send '{"event":"ping"}' && "$(ui_client)" send '{"event":"ping"}' | grep -q '"sessions":2'; then
  ok "the app is counting both turns"
else bad "the app is counting both turns" "$("$(ui_client)" send '{"event":"ping"}')"; fi

"$REPO/brb" reset >/dev/null
if "$(ui_client)" send '{"event":"ping"}' | grep -q '"sessions":0'; then
  ok "brb reset makes the app let go of them too"
else bad "brb reset makes the app let go of them too" "$("$(ui_client)" send '{"event":"ping"}')"; fi

# Warming the logo cache ahead of a recording, so the first panel has no flicker.
assert_ok "the app accepts a warm event" "ui_send '{\"event\":\"warm\"}'"

# Stop clears the session so the menu bar stops counting.
assert_ok "the app accepts a stop event" "ui_send \"\$(ui_json event stop session t4)\""

# The demo commands are how people try brb before a real turn, so they have to
# show the app's UI too, not the old dialogs.
fresh_log
"$REPO/brb" panel >/dev/null 2>&1
assert_log "" "panel shown for sid=" "brb panel opens the app's panel"

fresh_log
"$REPO/brb" alert "A test callback." >/dev/null 2>&1
assert_log "" "callback card shown" "brb alert opens the app's callback card"

# One panel is shared by every session, so it may only come down when the last
# one finishes.
note "several sessions at once"
fresh_log
hook on-start.sh '{"session_id":"m1","cwd":"/tmp/one"}'
hook on-start.sh '{"session_id":"m2","cwd":"/tmp/two"}'
hook on-done.sh  '{"session_id":"m1","last_assistant_message":"First done."}'
assert_log "" "panel stays: still busy" "the panel stays up while another session works"
fresh_log
hook on-done.sh  '{"session_id":"m2","last_assistant_message":"Second done."}'
assert_no_log "" "panel stays" "and comes down when the last one finishes"

# Claude blocked on you is a different signal from a finished turn.
note "attention rules"
fresh_log
hook on-start.sh '{"session_id":"a1","cwd":"/tmp/one"}'
hook on-attention.sh '{"session_id":"a1","notification_type":"permission_prompt"}'
assert_log "" "re-armed the panel (once per turn)" "answering a prompt re-arms the panel"
fresh_log
hook on-attention.sh '{"session_id":"a1","notification_type":"permission_prompt"}'
assert_log "" "already re-armed this turn" "but only once per turn"

fresh_log
hook on-attention.sh '{"session_id":"a1","notification_type":"idle_prompt"}'
assert_log    "" "idle but you never left" "idle stays silent when you never took a break"
assert_no_log "" "PINGING"                 "and nothing is pinged"

fresh_log
date +%s > "$SANDBOX/state/left/a1"
BRB_FAKE_FRONT="com.example.Browser" hook on-attention.sh '{"session_id":"a1","notification_type":"idle_prompt"}'
assert_log "" "PINGING type=idle_prompt" "idle does ping when the panel sent you away"

# And the mirror: at the terminal, Claude blocked on you stays quiet, since you
# can already see it.
fresh_log
BRB_FAKE_FRONT="$(cat "$SANDBOX/state/term/a1")" hook on-attention.sh '{"session_id":"a1","notification_type":"permission_prompt"}'
assert_no_log "" "PINGING" "at the terminal, a permission prompt is not pinged"
rm -f "$SANDBOX"/state/active/* "$SANDBOX"/state/left/* "$SANDBOX"/state/rearm/*

# --- 3. the escape hatches --------------------------------------------------

note "escape hatches"
fresh_log
BRB_UI=0 hook on-start.sh '{"session_id":"t5","cwd":"/tmp/demo"}'
date +%s > "$SANDBOX/state/left/t5"
BRB_UI=0 BRB_DRY=1 BRB_FAKE_FRONT="com.example.Browser" hook on-done.sh \
  '{"session_id":"t5","last_assistant_message":"Done."}'
assert_log "" "PINGING (banner" "BRB_UI=0 bypasses the app and falls back to a banner"

fresh_log
touch "$SANDBOX/OFF"
hook on-start.sh '{"session_id":"t6","cwd":"/tmp/demo"}'
assert_log     "" "OFF, ignoring" "brb off stops the hooks before anything is drawn"
assert_no_file "and no session is marked working" "$SANDBOX/state/active/t6"
rm -f "$SANDBOX/OFF"

# --- 4. the app survives what the hooks throw at it -------------------------

note "the app keeps its footing"
assert_ok "a done event for a session it never saw is still handled" \
  "ui_send \"\$(ui_json event done session ghost message 'Turn complete.' owner com.apple.Terminal)\""
assert_ok "a panel event with no session is still handled" \
  "ui_send \"\$(ui_json event panel session '')\""
assert_ok "the app is still alive afterwards" "kill -0 $APP_PID"
assert_ok "and still answering"               "ui_up"

# The app can die without cleaning up after itself. A leftover socket file must
# not swallow the panel.
note "a stale socket"
kill -9 "$APP_PID" 2>/dev/null
wait "$APP_PID" 2>/dev/null
APP_PID=""
assert_file  "the socket file outlives the killed app" "$SANDBOX/state/ui.sock"
assert_fails "ui_send fails fast on a dead socket"     "ui_send '{\"event\":\"ping\"}'"

fresh_log
BRB_DRY=1 hook on-start.sh '{"session_id":"s1","cwd":"/tmp/one"}'
BRB_DRY=1 "$REPO/lib/watch.sh" s1
assert_log "" "DRY: would show panel" "and the watcher still gets as far as the panel"
rm -f "$SANDBOX/state/ui.sock" "$SANDBOX"/state/active/*

# --- the plugin installs and updates its own app ---------------------------

note "the app installs itself"
WANT=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$REPO/.claude-plugin/plugin.json" | head -1)
fake_app() {  # fake_app <dir> <version>: a bundle with just enough to pass
  mkdir -p "$1/brb.app/Contents/MacOS"
  printf '#!/bin/sh\n' > "$1/brb.app/Contents/MacOS/brb"; chmod +x "$1/brb.app/Contents/MacOS/brb"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $2" "$1/brb.app/Contents/Info.plist" >/dev/null
}
fake_app "$SANDBOX/rel" "$WANT"
ditto -ck --keepParent "$SANDBOX/rel/brb.app" "$SANDBOX/rel/brb.app.zip"
export BRB_APPS_DIR="$SANDBOX/apps"; mkdir -p "$BRB_APPS_DIR"
export BRB_APP_URL="file://$SANDBOX/rel/brb.app.zip"
app_ver() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BRB_APPS_DIR/brb.app/Contents/Info.plist" 2>/dev/null; }
syncs() { grep -c "app sync" "$SANDBOX/state/brb.log" 2>/dev/null; }

fresh_log
BRB_DRY=1 hook on-session.sh '{}'
assert_log "" "DRY: would install app $WANT (have: none)" "a dry run only says what it would install"
assert_no_file "and installs nothing" "$BRB_APPS_DIR/brb.app"

fresh_log
hook on-session.sh '{}'
assert_ok  "a first session installs the app"            '[ "$(app_ver)" = "$WANT" ]'
assert_log "" "app sync: installed $WANT" "and logs it"

fresh_log
hook on-session.sh '{}'
assert_ok  "a current app is left alone, silently"        '[ "$(syncs)" = 0 ]'

rm -rf "$BRB_APPS_DIR/brb.app"; fake_app "$BRB_APPS_DIR" 0.0.1
echo "$(date +%s)" > "$SANDBOX/state/active/busy"
fresh_log
hook on-session.sh '{}'
assert_ok  "an update waits while a turn is running"     '[ "$(app_ver)" = 0.0.1 ]'
assert_log "" "waits, a turn is running" "and says why"
rm -f "$SANDBOX/state/active/busy"
hook on-session.sh '{}'
assert_ok  "then updates to the plugin's version"        '[ "$(app_ver)" = "$WANT" ]'
assert_log "" "app sync: updated 0.0.1 -> $WANT" "and logs the update"

rm -rf "$BRB_APPS_DIR/brb.app"
fresh_log
BRB_APP_URL="file://$SANDBOX/rel/missing.zip" hook on-session.sh '{}'
BRB_APP_URL="file://$SANDBOX/rel/missing.zip" hook on-session.sh '{}'
assert_ok  "a missing release is tried once an hour, not every session" '[ "$(syncs)" = 1 ]'
assert_no_file "and installs nothing" "$BRB_APPS_DIR/brb.app"
rm -f "$SANDBOX"/state/app-sync.*

fake_app "$SANDBOX/old" 0.0.2; ditto -ck --keepParent "$SANDBOX/old/brb.app" "$SANDBOX/old/brb.app.zip"
fresh_log
BRB_APP_URL="file://$SANDBOX/old/brb.app.zip" hook on-session.sh '{}'
assert_no_file "a download of the wrong version is not installed" "$BRB_APPS_DIR/brb.app"
rm -f "$SANDBOX"/state/app-sync.*

echo 'AUTO_APP=0' > "$SANDBOX/config.sh"
fresh_log
hook on-session.sh '{}'
assert_log "" "AUTO_APP=0, skipping" "AUTO_APP=0 turns it off"
assert_no_file "and installs nothing" "$BRB_APPS_DIR/brb.app"
rm -f "$SANDBOX/config.sh"
unset BRB_APPS_DIR BRB_APP_URL

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
