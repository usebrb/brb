# Shared helpers. Sourced by the CLI, the hooks and the UI scripts.
# Relocatable: nothing here assumes a particular install path.

# BRB_HOME = where this package lives. BRB_CONF = per-user config + state.
if [ -z "${BRB_HOME:-}" ]; then
  _src="${BASH_SOURCE[0]}"
  BRB_HOME="$(cd "$(dirname "$_src")/.." && pwd)"
fi
BRB_CONF="${BRB_CONF:-$HOME/.claude/brb}"
STATE="$BRB_CONF/state"

PY=/usr/bin/python3
OSA=/usr/bin/osascript
AFPLAY=/usr/bin/afplay
OPEN=/usr/bin/open
SOUNDS=/System/Library/Sounds

# Defaults, overridable from $BRB_CONF/config.sh
DEFAULT_DELAY=10
SOUND_DONE=Glass
SOUND_ATTENTION=Ping
TITLE_DONE="Claude is done"
TITLE_ATTENTION="Claude needs you"
PANEL_TITLE="Claude is working…"
[ -f "$BRB_CONF/config.sh" ] && . "$BRB_CONF/config.sh"

mkdir -p "$STATE/active" "$STATE/shown" "$STATE/term" "$STATE/left"

LOG="$STATE/brb.log"
log() { printf '%s [%-9s] %s\n' "$(date '+%H:%M:%S')" "${BRB_TAG:-?}" "$*" >> "$LOG" 2>/dev/null; }

is_off() { [ -f "$BRB_CONF/OFF" ]; }
is_dry() { [ -n "${BRB_DRY:-}" ]; }

items_file() {
  [ -f "$BRB_CONF/items.txt" ] && { printf '%s' "$BRB_CONF/items.txt"; return; }
  printf '%s' "$BRB_HOME/share/items.txt"
}

# Hook payload on stdin -> shell assignments to eval.
parse_hook_json() {
  "$PY" -c '
import sys, json, shlex, re
try: d = json.load(sys.stdin)
except Exception: d = {}
def g(k): return str(d.get(k) or "")
print("HK_SESSION=" + shlex.quote(g("session_id")))
print("HK_NTYPE="   + shlex.quote(g("notification_type")))
print("HK_CWD="     + shlex.quote(g("cwd")))
t = g("last_assistant_message")
t = re.sub(r"```.*?```", " ", t, flags=re.S)
t = re.sub(r"```.*", " ", t, flags=re.S)
t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
t = re.sub(r"`([^`]*)`", r"\1", t)
t = re.sub(r"^\s*[#>|*-]+\s*", " ", t, flags=re.M)
t = re.sub(r"[*_~]{1,3}", "", t)
t = " ".join(t.split())
if len(t) > 160:
    t = t[:160].rsplit(" ", 1)[0].rstrip(".,;:-") + "…"
print("HK_LAST=" + shlex.quote(t))
' 2>/dev/null
}

# Quote for AppleScript.
as_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

# --- who owns this session -------------------------------------------------
# Walk the process tree to the owning terminal app. This is a fact, unlike
# "whatever is frontmost", which is only a guess about focus at hook time.
owning_terminal_bundle() {
  local pid=$$ ppid comm appdir i=0
  while [ "$i" -lt 12 ]; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$ppid" in ''|0|1) break ;; esac
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null)
    case "$comm" in
      *.app/Contents/MacOS/*)
        appdir="${comm%%.app/Contents/MacOS/*}.app"
        /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' \
          "$appdir/Contents/Info.plist" 2>/dev/null
        return 0 ;;
    esac
    pid="$ppid"; i=$((i+1))
  done
  return 1
}

frontmost_bundle() {
  [ -n "${BRB_FAKE_FRONT:-}" ] && { printf '%s' "$BRB_FAKE_FRONT"; return 0; }
  "$OSA" -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null
}

# Bundle ids differ in case between LaunchServices and System Events.
same_app() {
  local a b
  a=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  b=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  [ -n "$a" ] && [ "$a" = "$b" ]
}

default_browser_id() {
  local cached="$STATE/browser" bid
  [ -s "$cached" ] && { cat "$cached"; return 0; }
  bid=$("$PY" -c '
import subprocess, plistlib, os
p = os.path.expanduser("~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
try:
    x = subprocess.run(["plutil","-convert","xml1","-o","-",p], capture_output=True).stdout
    for h in plistlib.loads(x).get("LSHandlers", []):
        if h.get("LSHandlerURLScheme") == "https":
            print(h.get("LSHandlerRoleAll","")); break
except Exception: pass' 2>/dev/null)
  [ -n "$bid" ] && printf '%s' "$bid" > "$cached"
  printf '%s' "$bid"
}

activate_bundle() {
  [ -n "$1" ] || return 0
  "$OSA" -e "tell application id $(as_str "$1") to activate" >/dev/null 2>&1
  return 0
}
activate_app() {
  [ -n "$1" ] || return 0
  "$OSA" -e "tell application $(as_str "$1") to activate" >/dev/null 2>&1
  return 0
}

# --- timer -----------------------------------------------------------------
current_delay() { cat "$STATE/delay" 2>/dev/null || echo "$DEFAULT_DELAY"; }

fmt_delay() {
  local s="$1"
  if [ "$s" -lt 60 ]; then echo "${s}s"
  elif [ $((s % 60)) -eq 0 ]; then echo "$((s / 60))m"
  else echo "$((s / 60))m$((s % 60))s"; fi
}

parse_delay() {
  "$PY" -c '
import sys, re
t = sys.argv[1].strip().lower().replace(" ", "")
if re.fullmatch(r"\d+", t):
    v = int(t)
else:
    m = re.fullmatch(r"(?:(\d+)m)?(?:(\d+)s)?", t)
    if not m or not any(m.groups()): sys.exit(1)
    v = int(m.group(1) or 0) * 60 + int(m.group(2) or 0)
if not (3 <= v <= 86400): sys.exit(1)
print(v)
' "$1" 2>/dev/null
}

# --- process / dialog plumbing ---------------------------------------------
spawn_detached() {
  # Deliberately NOT setsid: a setsid'd process loses its GUI session context
  # and `open` then launches apps in the background instead of foregrounding.
  ( nohup "$@" >/dev/null 2>&1 & ) >/dev/null 2>&1
  return 0
}

osa_tracked() {
  local out="$1" script="$2" pid rc
  "$OSA" -e "$script" > "$out" 2>/dev/null &
  pid=$!
  echo "$pid" > "$STATE/panel.pid"
  wait "$pid"; rc=$?
  [ "$(cat "$STATE/panel.pid" 2>/dev/null)" = "$pid" ] && rm -f "$STATE/panel.pid"
  return $rc
}

kill_panel() {
  local pid; pid=$(cat "$STATE/panel.pid" 2>/dev/null)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -f "$STATE/panel.pid"; return 0
}

kill_done_dialog() {
  local pid; pid=$(cat "$STATE/done.pid" 2>/dev/null)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -f "$STATE/done.pid"; return 0
}

notify() {
  local title="$1" msg="$2" sound="${3:-Glass}"
  is_dry && { log "DRY: would notify [$title] $msg"; return 0; }
  [ -f "$SOUNDS/$sound.aiff" ] && "$AFPLAY" "$SOUNDS/$sound.aiff" >/dev/null 2>&1 &
  "$OSA" -e "display notification $(as_str "$msg") with title $(as_str "$title")" >/dev/null 2>&1
  return 0
}
