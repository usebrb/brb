#!/bin/bash
# Tests for the `brb` CLI, including the `brb app` commands that manage the
# menu bar app. Read-only: nothing here installs or launches anything.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
note(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

SANDBOX=$(mktemp -d /tmp/brb-cli-test.XXXXXX)
export BRB_CONF="$SANDBOX"
export BRB_QUIET=1
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/state"

brb() { "$REPO/brb" "$@" 2>&1; }
# Capture first, then match: `grep -q` closes the pipe early, and under
# pipefail that makes a perfectly good command look like it failed.
says() { local out; out=$(brb $1); case "$out" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
has() { if says "$1" "$2"; then ok "$3"; else bad "$3" "'$2' missing from: brb $1"; fi; }

echo "brb CLI tests   sandbox: $SANDBOX"

note "help"
has "help" "brb app"    "help mentions the app commands"
has "help" "brb timer"  "help still lists the day-to-day commands"
has "help" "brb doctor" "help still lists doctor"

note "the app commands"
has "app"        "menu bar app" "brb app reports on the menu bar app"
has "app status" "menu bar app" "brb app status is the same report"
if says "app nonsense" "unknown"; then ok "an unknown app subcommand is rejected"
else bad "an unknown app subcommand is rejected"; fi

note "timer"
if says "timer 45s" "45s"; then ok "the timer can be set"; else bad "the timer can be set"; fi
if [ "$(cat "$SANDBOX/state/delay")" = 45 ]; then ok "and lands in the file the app reads"
else bad "and lands in the file the app reads" "delay=$(cat "$SANDBOX/state/delay" 2>/dev/null)"; fi
if says "timer banana" "can't read"; then ok "junk is rejected"; else bad "junk is rejected"; fi

note "status"
has "status" "app:" "status has a line for the menu bar app"
has "status" "break timer" "status still reports the timer"

note "on / off"
brb off >/dev/null
if [ -f "$SANDBOX/OFF" ]; then ok "brb off writes the kill switch"; else bad "brb off writes the kill switch"; fi
brb on >/dev/null
if [ ! -f "$SANDBOX/OFF" ]; then ok "brb on removes it"; else bad "brb on removes it"; fi

note "the commands that existed before the app still work"
# brb matrix runs every decision path with no UI at all.
if says "matrix" "Turn finished"; then ok "matrix prints the decision table"; else bad "matrix prints the decision table"; fi
if says "matrix" "never saw the panel"; then ok "and still covers every row"; else bad "and still covers every row"; fi

# brb items seeds the user's own copy rather than editing the shipped one.
EDITOR=true brb items >/dev/null
if [ -f "$SANDBOX/items.txt" ]; then ok "items seeds a user copy"; else bad "items seeds a user copy"; fi
if grep -q "|" "$SANDBOX/items.txt"; then ok "and it has real entries in it"; else bad "and it has real entries in it"; fi

# brb reset clears stuck sessions.
mkdir -p "$SANDBOX/state/active" "$SANDBOX/state/left"
date +%s > "$SANDBOX/state/active/stuck"
date +%s > "$SANDBOX/state/left/stuck"
brb reset >/dev/null
if [ ! -e "$SANDBOX/state/active/stuck" ] && [ ! -e "$SANDBOX/state/left/stuck" ]; then
  ok "reset clears stuck sessions"
else bad "reset clears stuck sessions"; fi
if [ -f "$SANDBOX/state/delay" ]; then ok "and keeps your timer"; else bad "and keeps your timer"; fi

# The log is still just a file being tailed.
: > "$SANDBOX/state/brb.log"
echo "12:00:00 [cli      ] a line for the tests" >> "$SANDBOX/state/brb.log"
if says "log" "a line for the tests"; then ok "log shows the decision log"; else bad "log shows the decision log"; fi

if brb nonsense >/dev/null 2>&1; then bad "an unknown command exits non-zero"
else ok "an unknown command exits non-zero"; fi
if says "nonsense" "unknown command"; then ok "and says so"; else bad "and says so"; fi

# The interactive demos are still listed, even though they need a person.
has "help" "brb panel" "panel is still offered"
has "help" "brb demo"  "demo is still offered"
has "help" "brb seed"  "seed is still offered"

note "brb film: setting the scene and putting it back"
# The shoot swaps in a short list and a fast timer, and must hand back exactly
# what was there before. Under BRB_QUIET it never touches Finder.
printf '🎹 Piano|https://example.com\n' > "$SANDBOX/items.txt"
brb timer 45s >/dev/null
brb film prep >/dev/null
if [ -f "$SANDBOX/film/items.txt.bak" ]; then ok "prep backs up the item list"; else bad "prep backs up the item list"; fi
if grep -q "Piano" "$SANDBOX/film/items.txt.bak"; then ok "and the backup is the real list"; else bad "and the backup is the real list"; fi
if ! grep -q "Piano" "$SANDBOX/items.txt" && grep -q "x.com" "$SANDBOX/items.txt"; then ok "the film list is in place"
else bad "the film list is in place"; fi
if grep -c "|" "$SANDBOX/items.txt" | grep -q "^3$"; then ok "and it is three sites, no notes"; else bad "and it is three sites, no notes" "$(cat "$SANDBOX/items.txt")"; fi
if [ "$(cat "$SANDBOX/state/delay")" = 3 ]; then ok "the timer is at the floor"; else bad "the timer is at the floor"; fi
if [ "$(cat "$SANDBOX/film/delay.bak")" = 45 ]; then ok "and the old timer is remembered"; else bad "and the old timer is remembered"; fi

brb film prep >/dev/null
if grep -q "Piano" "$SANDBOX/film/items.txt.bak"; then ok "a second prep does not clobber the backup"
else bad "a second prep does not clobber the backup"; fi

has "film prep" "Grayscale" "prep prints the checklist"
has "film"      "prep"      "film with no verb explains itself"

brb film restore >/dev/null
if grep -q "Piano" "$SANDBOX/items.txt"; then ok "restore brings the list back"; else bad "restore brings the list back"; fi
if [ "$(cat "$SANDBOX/state/delay")" = 45 ]; then ok "and the timer"; else bad "and the timer"; fi
if [ ! -d "$SANDBOX/film" ]; then ok "and leaves nothing behind"; else bad "and leaves nothing behind"; fi
if says "film restore" "nothing to restore"; then ok "restore without prep says so"; else bad "restore without prep says so"; fi

# A user with no list of their own must not end up with the film list as theirs.
rm -f "$SANDBOX/items.txt"
brb film prep >/dev/null; brb film restore >/dev/null
if [ ! -f "$SANDBOX/items.txt" ]; then ok "restore removes the film list when there was none before"
else bad "restore removes the film list when there was none before"; fi

note "hooks that predate the app"
# A checkout that is newer than the installed plugin is the normal state during
# development, and it is why people see the old panel and the new one in the
# same afternoon.
. "$REPO/lib/common.sh"
OLD=$(mktemp -d /tmp/brb-old.XXXX); mkdir -p "$OLD/lib"
echo 'is_off() { false; }' > "$OLD/lib/common.sh"
if hooks_know_app "$REPO"; then ok "this checkout is app-aware"; else bad "this checkout is app-aware"; fi
if hooks_know_app "$OLD"; then bad "an older install is spotted"; else ok "an older install is spotted"; fi
rm -rf "$OLD"

# A plugin update leaves the previous version in the cache. Only the one Claude
# Code would actually run counts, or doctor warns about hooks nobody runs.
FAKE=$(mktemp -d /tmp/brb-cache.XXXX)
mkdir -p "$FAKE/brb/brb/1.1.9/lib" "$FAKE/brb/brb/1.2.0/lib" "$FAKE/brb/brb/1.10.0/lib"
echo 'is_off() { false; }'     > "$FAKE/brb/brb/1.1.9/lib/common.sh"
echo 'ui_send() { return 1; }' > "$FAKE/brb/brb/1.2.0/lib/common.sh"
echo 'ui_send() { return 1; }' > "$FAKE/brb/brb/1.10.0/lib/common.sh"
roots=$(installed_hook_roots "$FAKE" /dev/null)
case "$roots" in
  *1.10.0*) ok "the newest cached version is the one checked" ;;
  *)        bad "the newest cached version is the one checked" "got: $roots" ;;
esac
case "$roots" in
  *1.1.9*) bad "superseded versions are ignored" "got: $roots" ;;
  *)       ok "superseded versions are ignored" ;;
esac
rm -rf "$FAKE"

note "doctor"
if says "doctor" "menu bar app"; then ok "doctor checks the app"; else bad "doctor checks the app"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
