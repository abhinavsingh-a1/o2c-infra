#!/usr/bin/env bash
# Remove the platform from the kind cluster "o2c": the root Application (cascading to
# every Application and its resources), the o2c-* namespaces, Argo CD and Kyverno.
# The cluster itself stays (make cluster-down in o2c-app deletes it); Docker Compose
# and its data are not touched.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_cluster

echo "== Argo CD applications"
if k get crd applications.argoproj.io > /dev/null 2>&1; then
  k -n argocd delete application o2c-root --ignore-not-found --wait=true --timeout=5m
  k -n argocd delete applicationsets.argoproj.io --all --ignore-not-found
  k -n argocd delete applications.argoproj.io --all --ignore-not-found --timeout=5m
fi

echo "== namespaces"
for env in "${ENVIRONMENTS[@]}"; do
  k delete namespace "o2c-$env" --ignore-not-found --wait=true --timeout=5m
done

echo "== Argo CD"
h uninstall argocd --namespace argocd --ignore-not-found --wait
k delete namespace argocd --ignore-not-found --timeout=5m

echo "== Kyverno (and its policies)"
k delete clusterpolicies.kyverno.io --all --ignore-not-found 2> /dev/null || true
h uninstall kyverno --namespace kyverno --ignore-not-found --wait
k delete namespace kyverno --ignore-not-found --timeout=5m

echo "Platform removed; the kind cluster '$CLUSTER' is still running."
