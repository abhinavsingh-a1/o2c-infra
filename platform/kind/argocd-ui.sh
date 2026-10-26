#!/usr/bin/env bash
# Argo CD UI at http://localhost:18081 (port-forward; Ctrl+C stops it).
# Prints the initial admin password (a local, generated secret of this kind cluster).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_cluster

password=$(k -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo "Argo CD: http://localhost:18081"
echo "user: admin"
echo "password: $password"
exec kubectl --context "$CONTEXT" -n argocd port-forward svc/argocd-server 18081:80
