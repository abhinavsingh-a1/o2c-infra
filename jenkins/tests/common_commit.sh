#!/usr/bin/env bash
# Tests of common_commit (jenkins/lib.sh): the o2c-app commit common to all images.
#   jenkins/tests/common_commit.sh
set -uo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib.sh
source "$WORKSPACE/jenkins/lib.sh"

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
C=cccccccccccccccccccccccccccccccccccccccc
failures=0

# expect <name> <expected output, or "fail"> <stdin lines...>
expect() {
  local name="$1" want="$2" got status
  shift 2
  got=$(printf '%s\n' "$@" | common_commit 2> /dev/null)
  status=$?
  if [ "$want" = fail ]; then
    [ "$status" -ne 0 ] && { echo "ok   $name"; return; }
  else
    [ "$status" -eq 0 ] && [ "$got" = "$want" ] && { echo "ok   $name"; return; }
  fi
  echo "FAIL $name: status $status, output '$got', expected '$want'"
  failures=$((failures + 1))
}

expect "one commit for all images" "$A" \
  "agent $A 100" "ui $A 100"
expect "unchanged ui attested by two releases" "$B" \
  "agent $B 200" "ui $A 100" "ui $B 200"
expect "newest of several common commits" "$B" \
  "agent $A 100" "agent $B 200" "ui $B 200" "ui $A 100"
expect "newest by the latest attestation of a commit" "$A" \
  "agent $A 100" "agent $B 200" "ui $A 300" "ui $B 150"
expect "a commit attested twice for one image counts once" fail \
  "agent $A 100" "agent $A 110" "ui $B 200"
expect "no commit in common" fail \
  "agent $A 100" "ui $B 200" "erp $A 100" "erp $B 200"
expect "a commit missing from one image of three" fail \
  "agent $A 100" "agent $C 300" "ui $A 100" "ui $C 300" "erp $B 200"
expect "the common commit is not the newest of any image" "$A" \
  "agent $A 100" "agent $C 300" "ui $A 100" "ui $C 300" "erp $A 100" "erp $B 200"
expect "no attestations" fail

# The failure lists each image's commits
msg=$(printf '%s\n' "agent $A 100" "ui $B 200" "ui $C 300" | common_commit 2>&1 > /dev/null)
if [[ "$msg" == *"agent: ${A:0:12}"* && "$msg" == *"ui: ${B:0:12} ${C:0:12}"* ]]; then
  echo "ok   the failure lists each image's commits"
else
  echo "FAIL the failure lists each image's commits: $msg"
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo "all passed"
