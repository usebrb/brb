#!/bin/bash
# Optional. Puts the `brb` command on your PATH.
#
# The plugin ships the hooks, which is all brb needs to work. This only adds the
# command line for `brb park`, `brb windows`, `brb timer`, `brb matrix` and
# `brb log`. A plugin's bin/ joins the Bash tool's PATH, not your shell's, which
# is why this exists.
#
# It installs a wrapper rather than a symlink, so the command always runs
# whichever plugin version is currently installed instead of drifting from it.
set -euo pipefail
BIN="${1:-$HOME/.local/bin}"
mkdir -p "$BIN"
cat > "$BIN/brb" <<'WRAPPER'
#!/bin/bash
d=$(ls -d "$HOME"/.claude/plugins/cache/*/brb/*/ 2>/dev/null | sort -V | tail -1)
if [ -z "$d" ]; then
  echo "brb plugin is not installed. Run: claude plugin install brb@brb" >&2
  exit 1
fi
exec "$d/brb" "$@"
WRAPPER
chmod +x "$BIN/brb"
echo "installed $BIN/brb"
case ":$PATH:" in
  *":$BIN:"*) echo "run: brb status" ;;
  *) echo "NOTE: $BIN is not on your PATH. Add it:"
     echo "  echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.zshrc" ;;
esac
