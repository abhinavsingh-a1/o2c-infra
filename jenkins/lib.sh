# Shell helpers of the promotion pipelines (jenkins/Jenkinsfile.promote-*, o2c-app
# ADR-018). Sourced by their sh steps (bash) from the workspace root, a checkout of
# o2c-infra. Needs the tools of the Jenkins image (ansible/roles/jenkins) and from the
# pipeline: WORKSPACE, KUBECONFIG, GH_TOKEN, JENKINS_CONTAINER, JENKINS_HOME_VOLUME.
# Workspace layout: gitops/ (o2c-gitops main), o2c-app/ (the promoted commit), reports/.
# shellcheck shell=bash disable=SC2034  # settings are used by the Jenkinsfiles

# shellcheck source=../platform/kind/lib.sh
source "$WORKSPACE/platform/kind/lib.sh" # to_host

GITHUB_OWNER="abhinavsingh-a1"
APP_REPO="$GITHUB_OWNER/o2c-app"
GITOPS_REPO="$GITHUB_OWNER/o2c-gitops"
# Only images signed by o2c-app's release workflow on main are promoted (ADR-016)
RELEASE_WORKFLOW=".github/workflows/release.yml"
RELEASE_REF="refs/heads/main"
OIDC_ISSUER="https://token.actions.githubusercontent.com"
PROVENANCE="https://slsa.dev/provenance/v1"
YAMLLINT_VERSION="1.38.0" # the same as o2c-gitops's PR check
ZAP_IMAGE="zaproxy/zap-stable:2.17.0@sha256:030d3df57735dacbb83464854758e674dd9ad01d79d12a129a8e58b1fd384238"
K6_IMAGE="grafana/k6:1.8.2@sha256:00fdcebafbc86cb0137d429529b1caa401a02e09025f02fc74866fa6e2b004d8"
REPORTS="$WORKSPACE/reports"
# The host settings of o2c-app (make eval: ml/eval_gate.py --full and the services' settings
# it imports) as the Jenkins container reaches the Compose stack on the host. Kafka: 29092,
# the listener that advertises host.docker.internal (9092 advertises localhost).
APP_HOSTS=(
  LITELLM_BASE_URL=http://host.docker.internal:4000
  MLFLOW_TRACKING_URI=http://host.docker.internal:5000
  MLFLOW_S3_ENDPOINT_URL=http://host.docker.internal:8333
  LANGFUSE_HOST=http://host.docker.internal:3000
  ERP_BASE_URL=http://host.docker.internal:8100
  S3_ENDPOINT_URL=http://host.docker.internal:8333
  KAFKA_BOOTSTRAP=host.docker.internal:29092
)
GIT_AUTHOR=(-c user.name="o2c-jenkins" -c user.email="o2c-jenkins@users.noreply.github.com")

log() { echo "$*" >&2; }
fail() {
  echo "ERROR: $*" >&2
  return 1
}

# --- GitHub ---------------------------------------------------------------------------

# git with GH_TOKEN for github.com through gh (the token is never written to disk)
git_gh() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }

clone_gitops() {
  rm -rf "$WORKSPACE/gitops"
  git clone --quiet --depth 50 "https://github.com/$GITOPS_REPO.git" "$WORKSPACE/gitops"
}

# common_commit: stdin lines "service commit epoch", one per verified provenance
# attestation (an image unchanged across releases keeps its digest and has one per
# release commit). Prints the newest commit (latest attestation) that every service has;
# without one, prints each service's commits and fails. Tested by jenkins/tests/common_commit.sh.
common_commit() {
  local out
  if out=$(awk '
      NF < 2 { next }
      !seen[$1, $2]++ {
        if (!($1 in commits)) order[++services] = $1
        commits[$1] = commits[$1] " " substr($2, 1, 12)
        has[$2]++
      }
      $3 + 0 > newest[$2] + 0 { newest[$2] = $3 }
      END {
        for (c in has)
          if (has[c] == services && (best == "" || newest[c] + 0 > newest[best] + 0 \
              || (newest[c] + 0 == newest[best] + 0 && c > best))) best = c
        if (best != "") { print best; exit 0 }
        for (i = 1; i <= services; i++) printf "  %s:%s\n", order[i], commits[order[i]]
        exit 1
      }'); then
    [ -n "$out" ] || fail "no verified provenance to find an o2c-app commit in" || return 1
    echo "$out"
  else
    fail "the images have no o2c-app commit in common; o2c-app commits of each image's build provenance:
$out"
  fi
}

# release_commit <images file>: verifies every image (lines "service repository@digest
# ...") - cosign signature and SLSA provenance of the release workflow on main - and
# prints the newest o2c-app commit that all of them have a verified provenance for.
release_commit() {
  local service image rest attested=() lines commit
  while read -r service image rest; do
    [ -n "$service" ] || continue
    cosign verify "$image" \
      --certificate-identity "https://github.com/$APP_REPO/$RELEASE_WORKFLOW@$RELEASE_REF" \
      --certificate-oidc-issuer "$OIDC_ISSUER" > /dev/null 2>&1 \
      || fail "$service: no valid signature of $RELEASE_WORKFLOW on main for $image" || return 1
    # Every verified attestation: "commit epoch" (the epoch of its latest verified timestamp)
    lines=$(gh attestation verify "oci://$image" --repo "$APP_REPO" \
      --signer-workflow "$APP_REPO/$RELEASE_WORKFLOW" --source-ref "$RELEASE_REF" \
      --deny-self-hosted-runners --predicate-type "$PROVENANCE" --format json \
      | jq -er '.[].verificationResult
          | "\(.signature.certificate.sourceRepositoryDigest | select(test("^[0-9a-f]{40}$"))) \(
              [.verifiedTimestamps[]?.timestamp
                | try (sub("\\.[0-9]+"; "") | fromdateiso8601) catch 0] | max // 0)"') \
      || fail "$service: no valid build provenance for $image" || return 1
    log "verified $service $image (o2c-app $(cut -c1-12 <<< "$lines" | paste -sd ' '))"
    while read -r commit rest; do
      attested+=("$service $commit $rest")
    done <<< "$lines"
  done < "$1"
  [ "${#attested[@]}" -gt 0 ] || fail "no images in $1" || return 1
  commit=$(printf '%s\n' "${attested[@]}" | common_commit) || return 1
  log "promoted o2c-app commit: $commit (common to all images)"
  echo "$commit"
}

# checkout_app <commit>: o2c-app at the promoted commit in o2c-app/
checkout_app() {
  local dir="$WORKSPACE/o2c-app" file
  rm -rf "$dir"
  git init --quiet "$dir"
  git -C "$dir" fetch --quiet --depth 1 "https://github.com/$APP_REPO.git" "$1"
  git -C "$dir" checkout --quiet FETCH_HEAD
  for file in scripts/promote_values.py scripts/e2e_send_and_check.py; do
    [ -f "$dir/$file" ] || fail "o2c-app ${1:0:12} has no $file: promote a release made after ADR-018" || return 1
  done
}

# write_app_env <o2c-app .env> <destination>: the .env as the Jenkins container reaches the
# Compose stack on the host (host.docker.internal), for make eval and the integration test
write_app_env() {
  local line
  (
    umask 077
    {
      while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
          printf '%s=%s\n' "${BASH_REMATCH[2]}" "$(to_host "${BASH_REMATCH[3]}")"
        else
          printf '%s\n' "$line"
        fi
      done < "$1"
      echo "# Jenkins: the Compose stack on the host (later lines win)"
      printf '%s\n' "${APP_HOSTS[@]}"
    } > "$2"
  )
}

# env_value <.env> <name>: the value of the last <name>= line, without surrounding quotes;
# returns 1 if there is none
env_value() {
  local line value="" found=1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] \
      && [ "${BASH_REMATCH[2]}" = "$2" ]; then
      value="${BASH_REMATCH[3]}"
      found=0
    fi
  done < "$1"
  if [[ "$value" =~ ^\'(.*)\'$ || "$value" =~ ^\"(.*)\"$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$value"
  return "$found"
}

# export_app_hosts <o2c-app .env>: exports APP_HOSTS and the database URLs of the .env
# (its credentials, host host.docker.internal). Needed by make eval: some settings are
# read from the process environment only, not from .env (MLFLOW_TRACKING_URI in
# ml/eval_hybrid.py and agent/anomaly.py). Prints nothing.
export_app_hosts() {
  local setting name url
  for setting in "${APP_HOSTS[@]}"; do
    export "${setting?}"
  done
  for name in EVENTS_DATABASE_URL ERP_DATABASE_URL; do
    if url=$(env_value "$1" "$name"); then
      export "$name=$(to_host "$url")"
    fi
  done
}

# open_and_merge_pr <branch> <title> <body>: push the branch of gitops/ (with its commit),
# open a PR, wait until its checks pass, squash-merge it; prints the merge commit.
open_and_merge_pr() {
  local branch="$1" title="$2" body="$3" url n state
  git_gh -C "$WORKSPACE/gitops" push --quiet origin "$branch"
  url=$(gh pr create --repo "$GITOPS_REPO" --base main --head "$branch" --title "$title" --body "$body")
  log "PR: $url"
  # The checks show up a few seconds after the PR is opened
  for _ in $(seq 36); do
    n=$(gh pr view "$url" --json statusCheckRollup --jq '.statusCheckRollup | length')
    [ "$n" -gt 0 ] && break
    sleep 5
  done
  [ "$n" -gt 0 ] || fail "no checks started on $url" || return 1
  gh pr checks "$url" --watch --fail-fast --interval 10 >&2 \
    || fail "checks failed on $url; it stays open, nothing was deployed" || return 1
  gh pr merge "$url" --squash --delete-branch >&2
  for _ in $(seq 30); do
    state=$(gh pr view "$url" --json state,mergeCommit --jq '.state + " " + (.mergeCommit.oid // "")')
    if [[ "$state" == MERGED\ ?* ]]; then
      echo "${state#MERGED }"
      return 0
    fi
    sleep 2
  done
  fail "$url was not merged: $state"
}

# promote_pr <from-env> <to-env> <o2c-app commit>: envs/<to> := images of envs/<from>,
# replicas 1, through a PR; prints its merge commit (nothing if envs/<to> is unchanged)
promote_pr() {
  local from="$1" to="$2" commit="$3" short="${3:0:12}" branch changed
  (cd "$WORKSPACE/o2c-app" && uv run --only-dev python scripts/promote_values.py \
    "$WORKSPACE/gitops/envs/$from" "$WORKSPACE/gitops/envs/$to" --replicas 1) >&2
  if git -C "$WORKSPACE/gitops" diff --quiet; then
    log "envs/$to already runs these images with 1 replica: no PR"
    return 0
  fi
  mapfile -t changed < <(git -C "$WORKSPACE/gitops" diff --name-only)
  # The same check as o2c-gitops's PR workflow: a bad file fails here, not in a blocked PR
  (cd "$WORKSPACE/gitops" && uvx --from "yamllint==$YAMLLINT_VERSION" yamllint --strict -c .yamllint.yaml "${changed[@]}") >&2
  git -C "$WORKSPACE/gitops" diff --stat >&2
  branch="promote/$to-$short-$BUILD_NUMBER"
  git -C "$WORKSPACE/gitops" switch --quiet -c "$branch"
  git -C "$WORKSPACE/gitops" "${GIT_AUTHOR[@]}" commit --quiet -am "chore($to): promote o2c-app $short"
  open_and_merge_pr "$branch" "chore($to): promote o2c-app $short" \
    "Promotion by Jenkins $JOB_NAME #$BUILD_NUMBER ($BUILD_URL): envs/$to gets the images of envs/$from (o2c-app $commit; signatures and build provenance verified) and 1 replica."
}

# revert_pr <env> <merge commit> <reason>: a PR reverting a promotion; prints its merge commit
revert_pr() {
  local env="$1" sha="$2" reason="$3" branch="rollback/$1-$BUILD_NUMBER"
  git -C "$WORKSPACE/gitops" fetch --quiet origin main
  git -C "$WORKSPACE/gitops" switch --quiet -C "$branch" origin/main
  git -C "$WORKSPACE/gitops" "${GIT_AUTHOR[@]}" revert --no-edit "$sha" >&2
  open_and_merge_pr "$branch" "revert($env): roll back promotion ${sha:0:12}" \
    "Automatic rollback by Jenkins $JOB_NAME #$BUILD_NUMBER ($BUILD_URL): $reason. Reverts $sha."
}

# --- Argo CD and Kubernetes -----------------------------------------------------------

# argocd CLI through a port-forward to argocd-server (kubeconfig), session in the workspace
argocd_login() {
  export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --plaintext --config $WORKSPACE/.argocd/config"
  local password
  password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  argocd login --username admin --password "$password" > /dev/null
}

# sync_env <env>: refresh, sync and wait for every Application of the environment
sync_env() {
  local selector="o2c.io/environment=$1" apps app
  mapfile -t apps < <(argocd app list -l "$selector" -o name)
  [ "${#apps[@]}" -gt 0 ] || fail "no Argo CD applications with $selector" || return 1
  for app in "${apps[@]}"; do
    argocd app get "$app" --hard-refresh > /dev/null
  done
  argocd app sync -l "$selector" --prune --timeout 900 > /dev/null
  argocd app wait -l "$selector" --sync --health --timeout 900 > /dev/null
  argocd app list -l "$selector"
}

# assert_images <env> <images file>: every Deployment runs the image of the values file
assert_images() {
  local service image rest running
  while read -r service image rest; do
    [ -n "$service" ] || continue
    running=$(kubectl -n "o2c-$1" get deployment "$service" -o jsonpath='{.spec.template.spec.containers[0].image}')
    [ "$running" = "$image" ] || fail "o2c-$1/$service runs $running, expected $image" || return 1
    log "o2c-$1/$service runs $image"
  done < "$2"
}

PF_PIDS=()
# port_forward <namespace> <service> <local port> <service port>: in the background until
# stop_port_forwards (trap it on EXIT); returns once the local port answers
port_forward() {
  kubectl -n "$1" port-forward "svc/$2" "$3:$4" > "$REPORTS/port-forward-$1-$2.log" 2>&1 &
  PF_PIDS+=("$!")
  for _ in $(seq 60); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$3/" && return 0
    sleep 1
  done
  fail "port-forward to $1/svc/$2 did not answer on 127.0.0.1:$3"
}
stop_port_forwards() { [ "${#PF_PIDS[@]}" -eq 0 ] || kill "${PF_PIDS[@]}" 2> /dev/null || true; }

# smoke_test <env> <images file>: GET healthPath of every service through its Service
smoke_test() {
  local service image port path local_port=18300 urls=()
  while read -r service image port path; do
    [ -n "$service" ] || continue
    port_forward "o2c-$1" "$service" "$local_port" "$port"
    urls+=("http://127.0.0.1:$local_port$path")
    local_port=$((local_port + 1))
  done < "$2"
  (cd "$WORKSPACE/o2c-app" && uv run --only-dev python scripts/e2e_send_and_check.py health "${urls[@]}" --timeout 120)
}

# --- ZAP and k6: containers of the host's Docker in this container's network namespace
# (they reach the port-forwards on 127.0.0.1); the workspace comes from the Jenkins volume

workspace_in_volume() { echo "${WORKSPACE#"$JENKINS_HOME"/}${1:+/$1}"; }

# zap_baseline <name> <url>: passive baseline scan; fails on any high-risk alert
zap_baseline() {
  local name="$1" url="$2" status=0 high
  docker run --rm --network "container:$JENKINS_CONTAINER" \
    --mount "type=volume,src=$JENKINS_HOME_VOLUME,dst=/zap/wrk,volume-subpath=$(workspace_in_volume reports)" \
    "$ZAP_IMAGE" zap-baseline.py -t "$url" -P 8090 -m 2 -I -s \
    -r "zap-$name.html" -J "zap-$name.json" || status=$?
  # -I: warnings do not fail the scan; 3 and more mean ZAP itself failed
  [ "$status" -lt 3 ] || fail "ZAP could not scan $url (exit $status)" || return 1
  jq -r '.site[].alerts[] | "\(.riskdesc)\t\(.alert) (\(.count) URLs)"' "$REPORTS/zap-$name.json" | sort -u >&2
  high=$(jq '[.site[].alerts[] | select(.riskcode == "3")] | length' "$REPORTS/zap-$name.json")
  [ "$high" -eq 0 ] || fail "ZAP found $high high-risk alert(s) on $url (reports/zap-$name.html)"
}

# k6_run <name> <vus> <duration> <p95 ms> <url>...: thresholds p95 < <p95 ms>, errors < 1%
k6_run() {
  local name="$1" vus="$2" duration="$3" p95="$4"
  shift 4
  docker run --rm --network "container:$JENKINS_CONTAINER" --user "$(id -u):$(id -g)" \
    --mount "type=volume,src=$JENKINS_HOME_VOLUME,dst=/work,volume-subpath=$(workspace_in_volume)" \
    -e TARGETS="$*" -e VUS="$vus" -e DURATION="$duration" -e P95_MS="$p95" \
    -e SUMMARY="/work/reports/k6-$name.json" \
    "$K6_IMAGE" run --quiet /work/jenkins/k6/load.js
}

# --- ServiceNow (E13) -----------------------------------------------------------------

# servicenow_change <o2c-app commit>: a normal change request; prints its number.
# SERVICENOW_URL, SN_USER and SN_PASSWORD from the pipeline (credential servicenow).
servicenow_change() {
  jq -n --arg commit "$1" --arg build "$BUILD_URL" '{
      type: "normal",
      short_description: "Promote o2c-app \($commit[0:12]) to prod",
      description: "Jenkins promotion \($build): o2c-app \($commit), images verified (ADR-016, ADR-018).",
      category: "Software"
    }' \
    | curl -fsS --config <(printf 'user = "%s:%s"\n' "$SN_USER" "$SN_PASSWORD") \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data @- "${SERVICENOW_URL%/}/api/now/table/change_request" \
    | jq -er '.result.number'
}
