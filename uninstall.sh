#!/bin/bash
# Removes brb's hooks. Leaves the rest of your settings untouched.
set -euo pipefail
BRB_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || { echo "no $SETTINGS - nothing to do"; exit 0; }
cp "$SETTINGS" "$SETTINGS.bak"

/usr/bin/python3 - "$SETTINGS" "$BRB_HOME" <<'PYEOF'
import json, sys, collections
settings, home = sys.argv[1], sys.argv[2]
d = json.load(open(settings), object_pairs_hook=collections.OrderedDict)
hooks = d.get("hooks") or {}
LEGACY = ("on-start.sh", "on-done.sh", "on-attention.sh")
# Earlier layouts and names of this same tool, so a rename still cleans up.
LEGACY_DIRS = ("/.claude/afk/", "/.claude/brb/", "/claude-afk/", "/brb/")
def mine(entry):
    c = entry.get("command", "")
    if home in c:
        return True
    return c.endswith(LEGACY) and any(x in c for x in LEGACY_DIRS)
n = 0
for ev in list(hooks):
    groups = []
    for grp in hooks[ev]:
        kept = [e for e in grp.get("hooks", []) if not mine(e)]
        n += len(grp.get("hooks", [])) - len(kept)
        if kept: grp["hooks"] = kept; groups.append(grp)
    if groups: hooks[ev] = groups
    else: hooks.pop(ev)
if hooks: d["hooks"] = hooks
else: d.pop("hooks", None)
json.dump(d, open(settings,"w"), indent=2, ensure_ascii=False)
open(settings,"a").write("\n")
print(f"  removed {n} hook(s)")
PYEOF

rm -f "$HOME/.local/bin/brb" "$HOME/.local/bin/afk"
echo "uninstalled. Your config and logs are still in ${BRB_CONF:-$HOME/.claude/brb}"
echo "(delete that directory too if you want it gone completely)"
