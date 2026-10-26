#!/usr/bin/env bash
# Bootstrap the local platform on the kind cluster "o2c" (o2c-app ADR-017). Idempotent:
# run it again after a change; helm upgrade --install and kubectl apply converge.
#
#   1. Kyverno (pinned chart) - admission policies, synced later from o2c-gitops
#   2. Argo CD (pinned chart)
#   3. the root Application from o2c-gitops (app of apps): namespaces, policies and
#      one Application per service and environment
#
# Credentials are not in Git: run secrets.sh <namespace> for o2c-dev (and test/prod).
# Usage: platform/kind/bootstrap.sh
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_cluster

# ROOT_APP may point at another root Application, e.g. for a rehearsal against local repos
ROOT_APP="${ROOT_APP:-$REPOS/o2c-gitops/platform/argocd/root.yaml}"
[ -f "$ROOT_APP" ] || { echo "missing $ROOT_APP (o2c-gitops next to o2c-infra?)" >&2; exit 1; }

echo "== Kyverno $KYVERNO_CHART_VERSION"
h upgrade --install kyverno "$KYVERNO_CHART" \
  --version "$KYVERNO_CHART_VERSION" --namespace kyverno --create-namespace \
  --values "$HERE/kyverno-values.yaml" --wait --timeout 10m

echo "== Argo CD $ARGOCD_CHART_VERSION"
h upgrade --install argocd "$ARGOCD_CHART" \
  --version "$ARGOCD_CHART_VERSION" --namespace argocd --create-namespace \
  --values "$HERE/argocd-values.yaml" --wait --timeout 10m

echo "== root Application (o2c-gitops)"
k apply --namespace argocd -f "$ROOT_APP"

echo
echo "Done. Next:"
echo "  platform/kind/secrets.sh o2c-dev     # credentials from o2c-app/.env"
echo "  platform/kind/argocd-ui.sh           # http://localhost:18081"
