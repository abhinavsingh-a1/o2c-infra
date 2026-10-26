#!/usr/bin/env bash
# Create (or update) the Kubernetes Secrets every O2C service needs in one namespace,
# from ../o2c-app/.env (o2c-app ADR-017). Never prints a value.
#
#   platform/kind/secrets.sh o2c-dev        (also o2c-test, o2c-prod)
#
# The infrastructure stays in Docker Compose: hosts in URLs (localhost, 127.0.0.1 and
# the Compose service names) are rewritten to host.docker.internal, which pods reach.
# Secret names match secretName/secretFiles in o2c-gitops envs/<env>/<service>.yaml.
# Each service gets only the keys it reads; the LLM services get their own LiteLLM key.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_cluster

namespace="${1:-}"
case "$namespace" in
  o2c-dev | o2c-test | o2c-prod) ;;
  *) echo "usage: $0 o2c-dev|o2c-test|o2c-prod" >&2; exit 1 ;;
esac
ENV_FILE="${ENV_FILE:-$REPOS/o2c-app/.env}"
USERS_FILE="${USERS_FILE:-$REPOS/o2c-app/local/users.json}"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 1; }

# --- read .env: KEY=value, optional single or double quotes, no interpolation ---------
declare -A ENV=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
  key="${BASH_REMATCH[2]}"
  value="${BASH_REMATCH[3]}"
  if [[ "$value" =~ ^\'(.*)\'[[:space:]]*$ ]] || [[ "$value" =~ ^\"(.*)\"[[:space:]]*$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  ENV["$key"]="$value"
done < "$ENV_FILE"

need() {
  local key
  for key in "$@"; do
    [ -n "${ENV[$key]:-}" ] || { echo "$key is missing in $ENV_FILE" >&2; exit 1; }
  done
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

# secret <name> KEY=SOURCE_KEY ... : env-file built from .env (with host rewrite),
# then applied through a client-side dry run, so it is created or updated in place.
secret() {
  local name="$1" pair key source file="$TMP/$1.env"
  shift
  : > "$file"
  for pair in "$@"; do
    key="${pair%%=*}"
    source="${pair#*=}"
    need "$source"
    printf '%s=%s\n' "$key" "$(to_host "${ENV[$source]}")" >> "$file"
  done
  k -n "$namespace" create secret generic "$name" --from-env-file="$file" \
    --dry-run=client -o yaml | k apply -f - > /dev/null
  echo "secret/$name: $# keys"
}

# Optional per-service LiteLLM key (ml/litellm_keys.py), else the master key
llm_key() {
  if [ -n "${ENV[$1]:-}" ]; then echo "$1"; else echo "LITELLM_MASTER_KEY"; fi
}

k create namespace "$namespace" --dry-run=client -o yaml | k apply -f - > /dev/null

need POSTGRES_USER POSTGRES_PASSWORD
ENV[LITELLM_DATABASE_URL]="postgresql+psycopg://${ENV[POSTGRES_USER]}:${ENV[POSTGRES_PASSWORD]}@host.docker.internal:5432/litellm"

S3=(S3_ACCESS_KEY=S3_ACCESS_KEY S3_SECRET_KEY=S3_SECRET_KEY)
secret intake-secrets INTAKE_HMAC_SECRET=INTAKE_HMAC_SECRET "${S3[@]}"
secret classifier-secrets "LITELLM_MASTER_KEY=$(llm_key LITELLM_KEY_CLASSIFIER)" \
  EVENTS_DATABASE_URL=EVENTS_DATABASE_URL "${S3[@]}"
secret extractor-secrets "LITELLM_MASTER_KEY=$(llm_key LITELLM_KEY_EXTRACTOR)" \
  EVENTS_DATABASE_URL=EVENTS_DATABASE_URL "${S3[@]}"
secret agent-secrets "LITELLM_MASTER_KEY=$(llm_key LITELLM_KEY_AGENT)" \
  EVENTS_DATABASE_URL=EVENTS_DATABASE_URL AUTH_JWT_SECRET=AUTH_JWT_SECRET "${S3[@]}"
secret analytics-sink-secrets EVENTS_DATABASE_URL=EVENTS_DATABASE_URL \
  LITELLM_DATABASE_URL=LITELLM_DATABASE_URL GRAFANA_DB_PASSWORD=GRAFANA_DB_PASSWORD
secret audit-archiver-secrets EVENTS_DATABASE_URL=EVENTS_DATABASE_URL "${S3[@]}"
secret erp-mock-secrets ERP_DATABASE_URL=ERP_DATABASE_URL

# Reviewer accounts for the agent (agent.auth), mounted as /app/local/users.json
if [ -f "$USERS_FILE" ]; then
  k -n "$namespace" create secret generic agent-users --from-file=users.json="$USERS_FILE" \
    --dry-run=client -o yaml | k apply -f - > /dev/null
  echo "secret/agent-users: users.json"
else
  # The pod mounts this Secret, so it must exist: no accounts, nobody can log in
  echo "{}" > "$TMP/users.json"
  k -n "$namespace" create secret generic agent-users --from-file=users.json="$TMP/users.json"     --dry-run=client -o yaml | k apply -f - > /dev/null
  echo "secret/agent-users: empty (no $USERS_FILE, nobody can log in)" >&2
fi
