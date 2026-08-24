#!/bin/bash
# Registers brb's hooks in ~/.claude/settings.json.
# Idempotent: re-running replaces our entries and leaves everything else alone.
set -euo pipefail
BRB_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRB_CONF="${BRB_CONF:-$HOME/.claude/brb}"
SETTINGS="$HOME/.claude/settings.json"

[ "$(uname)" = "Darwin" ] || { echo "brb is macOS only (it uses osascript)." >&2; exit 1; }

mkdir -p "$BRB_CONF/state"/{active,shown,term,left}
if [ ! -f "$BRB_CONF/items.txt" ]; then
  cp "$BRB_HOME/share/items.txt" "$BRB_CONF/items.txt"
  echo "  created $BRB_CONF/items.txt  (edit this to change the panel)"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"

/usr/bin/python3 - "$SETTINGS" "$BRB_HOME" <<'PYEOF'
import json, sys, collections
settings, home = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(settings), object_pairs_hook=collections.OrderedDict)
except Exception:
    d = collections.OrderedDict()
hooks = d.get("hooks") or collections.OrderedDict()

LEGACY = ("on-start.sh", "on-done.sh", "on-attention.sh")
# Earlier layouts and names of this same tool, so a rename still cleans up.
LEGACY_DIRS = ("/.claude/afk/", "/.claude/brb/", "/claude-afk/", "/brb/")
def mine(entry):
    c = entry.get("command", "")
    if home in c:
        return True
    return c.endswith(LEGACY) and any(x in c for x in LEGACY_DIRS)

# Strip any previous install of ours, keep everyone else's hooks intact.
for ev in list(hooks):
    groups = []
    for grp in hooks[ev]:
        kept = [e for e in grp.get("hooks", []) if not mine(e)]
        if kept:
            grp["hooks"] = kept
            groups.append(grp)
    if groups: hooks[ev] = groups
    else: hooks.pop(ev)

def entry(script, timeout):
    return {"type": "command", "command": f"{home}/hooks/{script}",
            "async": True, "timeout": timeout}

# async so they never block a turn; the timeouts only cap how long the
# detached children (break timer, callback dialog) are allowed to live.
hooks.setdefault("UserPromptSubmit", []).append({"hooks": [entry("on-start.sh", 120)]})
hooks.setdefault("Stop", []).append({"hooks": [entry("on-done.sh", 660)]})
hooks.setdefault("Notification", []).append(
    {"matcher": "permission_prompt|agent_needs_input|idle_prompt",
     "hooks": [entry("on-attention.sh", 660)]})

d["hooks"] = hooks
json.dump(d, open(settings, "w"), indent=2, ensure_ascii=False)
open(settings, "a").write("\n")
print("  registered UserPromptSubmit, Stop, Notification")
PYEOF

# Put `brb` on PATH if we can do it without sudo.
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
ln -sf "$BRB_HOME/brb" "$BIN/brb"
echo "  linked $BIN/brb -> $BRB_HOME/brb"

echo
echo "installed. backup of your previous settings: $SETTINGS.bak"
case ":$PATH:" in
  *":$BIN:"*) echo "run:  brb status" ;;
  *) echo "NOTE: $BIN is not on your PATH. Either add it:"
     echo "        echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
     echo "      or just call it directly:  $BRB_HOME/brb status" ;;
esac
echo "Hooks load when a Claude session starts, so open a new one to pick them up."
