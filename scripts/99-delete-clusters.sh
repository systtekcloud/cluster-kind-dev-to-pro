#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-all}"

delete_cluster() {
  local name="$1"
  local context="kind-${name}"

  if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    echo ">>> Eliminando cluster: $name"
    kind delete cluster --name "$name"
  else
    echo "INFO: El cluster '$name' no existe. Saltando."
  fi

  # Limpiar contexto del kubeconfig si quedó huérfano
  if kubectl config get-contexts "$context" &>/dev/null; then
    kubectl config delete-context "$context" 2>/dev/null || true
    echo "INFO: Contexto $context eliminado del kubeconfig"
  fi
}

case "$TARGET" in
  dev)
    delete_cluster "dev-cluster"
    ;;
  pro)
    delete_cluster "pro-cluster"
    ;;
  all)
    delete_cluster "dev-cluster"
    delete_cluster "pro-cluster"
    ;;
  *)
    echo "Uso: $0 [dev|pro|all]"
    echo "  dev  — elimina solo dev-cluster"
    echo "  pro  — elimina solo pro-cluster"
    echo "  all  — elimina ambos clusters (por defecto)"
    exit 1
    ;;
esac

echo ""
echo "Clusters restantes:"
kind get clusters 2>/dev/null || echo "(ninguno)"
