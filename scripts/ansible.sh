#!/usr/bin/env bash
# Run a playbook of ansible/ in the Ansible runner image (o2c-app ADR-018): nothing to
# install on the host but Docker. The runner gets the host's Docker socket and joins the
# kind network, so it can build and start containers next to the cluster and reach them.
#
#   scripts/ansible.sh jenkins.yml [ansible-playbook options]
#   scripts/ansible.sh jenkins.yml --syntax-check
#
# The repos' parent directory is mounted read-only at /work (o2c-app/.env is read from
# there by the playbook; values never reach the output).
set -euo pipefail

INFRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS="$(cd "$INFRA/.." && pwd)"
IMAGE="o2c-ansible:local"
NETWORK="kind"

[ $# -ge 1 ] || { echo "usage: $0 <playbook.yml> [ansible-playbook options]" >&2; exit 1; }
docker network inspect "$NETWORK" > /dev/null 2>&1 \
  || { echo "Docker network '$NETWORK' not found: create the kind cluster first (make cluster-up in o2c-app)" >&2; exit 1; }

# Cached layers: fast, and a no-op when nothing changed
docker build --quiet --tag "$IMAGE" "$INFRA/ansible" > /dev/null

# Git Bash on Windows: docker wants a Windows path and no MSYS path conversion
if repos_host="$(cd "$REPOS" && pwd -W 2> /dev/null)"; then
  export MSYS_NO_PATHCONV=1
else
  repos_host="$REPOS"
fi
tty=()
[ -t 1 ] && tty=(--tty)

exec docker run --rm "${tty[@]}" \
  --network "$NETWORK" \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume "$repos_host:/work:ro" \
  --workdir /work/o2c-infra/ansible \
  --env ANSIBLE_CONFIG=/work/o2c-infra/ansible/ansible.cfg \
  --env ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-1}" \
  "$IMAGE" ansible-playbook "$@"
