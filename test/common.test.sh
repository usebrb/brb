#!/bin/bash
# Unit tests for the pure helpers in lib/common.sh: the timer parser and
# formatter. No UI, no hooks, nothing installed. Runs against a throwaway
# BRB_CONF so sourcing common.sh never touches your real config.
#
#   test/common.test.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
note(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

SANDBOX=$(mktemp -d /tmp/brb-common-test.XXXXXX)
export BRB_CONF="$SANDBOX"
export BRB_HOME="$REPO"
export BRB_QUIET=1
trap 'rm -rf "$SANDBOX"' EXIT

. "$REPO/lib/common.sh"

# parses "input" -> expected seconds
parses() {
  local got
  got=$(parse_delay "$1")
  if [ "$got" = "$2" ]; then ok "parse_delay '$1' -> $2"
  else bad "parse_delay '$1' -> $2" "got: '${got:-<empty>}'"; fi
}
# rejects "input": non-zero exit and nothing printed
rejects() {
  local got rc
  got=$(parse_delay "$1"); rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$got" ]; then ok "parse_delay rejects '$1'"
  else bad "parse_delay rejects '$1'" "rc=$rc out='$got'"; fi
}
# formats seconds -> expected string
formats() {
  local got
  got=$(fmt_delay "$1")
  if [ "$got" = "$2" ]; then ok "fmt_delay $1 -> $2"
  else bad "fmt_delay $1 -> $2" "got: '$got'"; fi
}

echo "brb common.sh tests   sandbox: $SANDBOX"

note "parse_delay: bare numbers are seconds"
parses "45"    45
parses "3"     3
parses "86400" 86400

note "parse_delay: units"
parses "45s"    45
parses "2m"     120
parses "1m30s"  90
parses "1m0s"   60
parses "0m45s"  45
parses "1440m"  86400

note "parse_delay: tolerant of case and whitespace"
parses " 10 "     10
parses "1M30S"    90
parses "1m 30s"   90
parses " 2 m "    120

note "parse_delay: the range is 3s to 24h"
parses  "3"     3
rejects "2"
rejects "0"
rejects "0s"
rejects "0m0s"
parses  "86400" 86400
rejects "86401"
rejects "1441m"
rejects "1440m1s"

note "parse_delay: junk is rejected"
rejects ""
rejects " "
rejects "banana"
rejects "m"
rejects "s"
rejects "ms"
rejects "-5"
rejects "1.5m"
rejects "1h"
rejects "30s1m"
rejects "1m1m"
rejects "10 seconds"
rejects "45x"

note "fmt_delay"
formats 0     "0s"
formats 3     "3s"
formats 59    "59s"
formats 60    "1m"
formats 61    "1m1s"
formats 90    "1m30s"
formats 119   "1m59s"
formats 120   "2m"
formats 3600  "60m"
formats 86400 "1440m"

note "fmt_delay output reparses to the same value"
for s in 3 45 60 90 120 3599 3600 86400; do
  back=$(parse_delay "$(fmt_delay "$s")")
  if [ "$back" = "$s" ]; then ok "$s -> $(fmt_delay "$s") -> $s"
  else bad "$s -> $(fmt_delay "$s") -> $s" "got: '$back'"; fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
