#!/usr/bin/env bash
set -euo pipefail

CLUSTERS=("dev-cluster" "pro-cluster")

show_cluster_status() {
  local name="$1"
  local context="kind-${name}"

  echo "════════════════════════════════════════════════════════"
  echo "  CLUSTER: $name"
  echo "════════════════════════════════════════════════════════"

  if ! kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    echo "  [NO EXISTE]"
    echo ""
    return
  fi

  echo ""
  echo "--- Nodos ---"
  kubectl --context="$context" get nodes -o wide 2>/dev/null || echo "  (error obteniendo nodos)"

  echo ""
  echo "--- Cilium (kube-system) ---"
  kubectl --context="$context" get pods -n kube-system \
    -l k8s-app=cilium \
    -o wide 2>/dev/null || echo "  (Cilium no instalado)"

  echo ""
  echo "--- MetalLB (metallb-system) ---"
  kubectl --context="$context" get pods -n metallb-system \
    -o wide 2>/dev/null || echo "  (MetalLB no instalado)"

  echo ""
  echo "--- Servicios LoadBalancer ---"
  kubectl --context="$context" get svc -A \
    --field-selector spec.type=LoadBalancer \
    -o wide 2>/dev/null || echo "  (ninguno)"

  echo ""
}

for cluster in "${CLUSTERS[@]}"; do
  show_cluster_status "$cluster"
done
