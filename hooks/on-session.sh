#!/bin/bash
# SessionStart: install the menu bar app if it's missing, or bring it up to
# the plugin's version after an update. Quiet when it's already current.
# macOS only; nothing to do elsewhere.
[ "$(uname)" = Darwin ] || exit 0
BRB_TAG=session
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
cat >/dev/null   # the payload isn't needed
app_sync
exit 0
