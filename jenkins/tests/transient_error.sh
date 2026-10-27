#!/usr/bin/env bash
# Tests of transient_error and retry_transient (jenkins/lib.sh): which argocd/kubectl
# failures are retried.
#   jenkins/tests/transient_error.sh
set -uo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib.sh
source "$WORKSPACE/jenkins/lib.sh"

failures=0
ok() { echo "ok   $1"; }
ko() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

# expect <name> <transient|real> <output>
expect() {
  if transient_error "$3"; then got=transient; else got=real; fi
  if [ "$got" = "$2" ]; then ok "$1"; else ko "$1: $got, expected $2"; fi
}

expect "cluster DNS timeout" transient \
  'level=fatal msg="rpc error: code = Unavailable desc = dns: A record lookup error: lookup argocd-repo-server on 10.96.0.10:53: dial udp 10.96.0.10:53: i/o timeout"'
expect "lookup error without rpc code" transient \
  'dial tcp: lookup argocd-server on 10.96.0.10:53: server misbehaving'
expect "i/o timeout" transient 'read tcp 127.0.0.1:41234->127.0.0.1:6443: i/o timeout'
expect "connection reset" transient 'read: connection reset by peer'
expect "connection refused" transient \
  'The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port? dial tcp 127.0.0.1:6443: connect: connection refused'
expect "context deadline exceeded" transient 'rpc error: code = DeadlineExceeded desc = context deadline exceeded'
expect "sync failed" real 'level=fatal msg="Operation has completed with phase: Failed"'
expect "sync failed mentioning a network error" real \
  'level=fatal msg="Operation has completed with phase: Failed": dial tcp 10.96.0.1:443: connect: connection refused'
expect "degraded health" real \
  "level=fatal msg=\"application 'o2c-prod-agent' health state has transitioned from Progressing to Degraded\""
expect "invalid manifest" real \
  'ComparisonError: Failed to load target state: error validating data: unknown field "replica"'
expect "the CLI's own timeout" real "level=fatal msg=\"timed out (900s) waiting for app \\\"o2c-prod-ui\\\"\""
expect "not found" real 'Error from server (NotFound): deployments.apps "ui" not found'
expect "no output" real ''

# retry_transient: fake commands, no pauses
RETRY_PAUSES=(0 0 0)
calls=0
flaky() { # fails transiently until attempt $1, then prints ok
  calls=$((calls + 1))
  [ "$RETRY_ATTEMPT" -ge "$1" ] && { echo ok; return 0; }
  echo "rpc error: code = Unavailable desc = dns: A record lookup error" >&2
  return 20
}
broken() {
  calls=$((calls + 1))
  echo 'Operation has completed with phase: Failed' >&2
  return 20
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
calls=0
retry_transient argocd flaky 3 > "$tmp/out" 2> "$tmp/log"
status=$? out=$(cat "$tmp/out") log_text=$(cat "$tmp/log")
if [ "$status" -eq 0 ] && [ "$out" = ok ] && [ "$calls" -eq 3 ] \
  && [[ "$log_text" == *"argocd: transient error, retry 2/4 in 0 s"* ]]; then
  ok "transient errors retried until success"
else
  ko "transient errors retried until success: status $status, output '$out', calls $calls, log: $log_text"
fi

calls=0
retry_transient argocd flaky 9 > /dev/null 2> "$tmp/log"
status=$? log_text=$(cat "$tmp/log")
if [ "$status" -eq 20 ] && [ "$calls" -eq 4 ] && [[ "$log_text" == *"giving up after 4 attempts"* ]]; then
  ok "fails after 4 attempts with the command's status"
else
  ko "fails after 4 attempts with the command's status: status $status, calls $calls, log: $log_text"
fi

calls=0
retry_transient argocd broken 2> /dev/null
status=$?
if [ "$status" -eq 20 ] && [ "$calls" -eq 1 ]; then
  ok "a real error fails at once"
else
  ko "a real error fails at once: status $status, calls $calls"
fi

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo "all passed"
