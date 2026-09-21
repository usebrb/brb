#!/bin/bash
# Everything: the app's unit tests, then the hook wiring end to end.
#
#   test/run.sh
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

echo "== shell syntax"
for f in "$REPO"/brb "$REPO"/lib/*.sh "$REPO"/hooks/*.sh "$REPO"/*.sh "$REPO"/test/*.sh; do
  bash -n "$f" || { echo "  syntax error in $f"; rc=1; }
done
[ "$rc" = 0 ] && echo "  ok"

if command -v swift >/dev/null 2>&1; then
  echo
  echo "== app unit tests"
  swift test --package-path "$REPO/app" 2>&1 | tail -1 || rc=1
else
  echo
  echo "== app unit tests: skipped (no swift toolchain)"
fi

echo
echo "== common.sh"
"$REPO/test/common.test.sh" || rc=1

if [ "$(uname)" = Darwin ]; then
  echo
  echo "== hook wiring"
  "$REPO/test/hooks.test.sh" || rc=1
  echo
  echo "== cli"
  "$REPO/test/cli.test.sh" || rc=1
else
  echo
  echo "== hook wiring: skipped (macOS only)"
fi

exit $rc
