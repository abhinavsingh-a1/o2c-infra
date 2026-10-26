# Shared settings for the platform/kind scripts (o2c-app ADR-017). Sourced, not run.
# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this

CLUSTER="o2c"
CONTEXT="kind-$CLUSTER"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS="$(cd "$HERE/../../.." && pwd)" # o2c-infra's parent: o2c-app, o2c-gitops

# Pinned charts from the projects' OCI registries (no helm repo state needed).
# kyverno 3.9.1 = Kyverno v1.19.1, sha256:720542b97bdbc2633535c2297332690d21cfbb944053eb1ec1f0dbe8e3895444
# argo-cd 10.10.3 = Argo CD v3.5.5, sha256:5630deeceb64418561304621ec616345e804f5668c4dcb80c205735d6e34c4f6
KYVERNO_CHART="oci://ghcr.io/kyverno/charts/kyverno"
KYVERNO_CHART_VERSION="3.9.1"
ARGOCD_CHART="oci://ghcr.io/argoproj/argo-helm/argo-cd"
ARGOCD_CHART_VERSION="10.10.3"

ENVIRONMENTS=(dev test prod)

# Every kubectl/helm call names the kind context: never the current one by accident
k() { kubectl --context "$CONTEXT" "$@"; }
h() { helm --kube-context "$CONTEXT" "$@"; }

require_cluster() {
  if ! kind get clusters 2> /dev/null | grep -qx "$CLUSTER"; then
    echo "kind cluster '$CLUSTER' not found: run make cluster-up in o2c-app" >&2
    exit 1
  fi
}
