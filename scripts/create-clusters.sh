#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-all}"

# Puertos clave a verificar antes de crear clusters
DEV_PORTS=(6450 9090 9091 9092 8440 8441 8442 2030 2031 2032 2090)
PRO_PORTS=(6451 9093 9094 9095 8450 8451 8452 2130 2131 2132 2190)

check_docker() {
  if ! docker info &>/dev/null; then
    echo "ERROR: Docker no está corriendo. Inicia Docker e intenta de nuevo."
    exit 1
  fi
}

check_ports() {
  local cluster="$1"
  shift
  local ports=("$@")
  local occupied=()

  for port in "${ports[@]}"; do
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      occupied+=("$port")
    fi
  done

  if [[ ${#occupied[@]} -gt 0 ]]; then
    echo "ERROR: Los siguientes puertos del cluster $cluster ya están en uso: ${occupied[*]}"
    echo "Libera los puertos o revisa si el cluster ya existe: kind get clusters"
    exit 1
  fi
}

create_cluster() {
  local name="$1"
  local config="$2"

  if kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    echo "INFO: El cluster '$name' ya existe. Saltando creación."
    return
  fi

  echo ">>> Creando cluster: $name"
  kind create cluster --config "$config"
  echo ">>> Cluster $name creado. Contexto: kind-${name}"
}

check_docker

case "$TARGET" in
  dev)
    check_ports "dev-cluster" "${DEV_PORTS[@]}"
    create_cluster "dev-cluster" "$ROOT_DIR/dev/kind/dev-cluster.yaml"
    ;;
  pro)
    check_ports "pro-cluster" "${PRO_PORTS[@]}"
    create_cluster "pro-cluster" "$ROOT_DIR/pro/kind/pro-cluster.yaml"
    ;;
  all)
    check_ports "dev-cluster" "${DEV_PORTS[@]}"
    check_ports "pro-cluster" "${PRO_PORTS[@]}"
    create_cluster "dev-cluster" "$ROOT_DIR/dev/kind/dev-cluster.yaml"
    create_cluster "pro-cluster" "$ROOT_DIR/pro/kind/pro-cluster.yaml"
    ;;
  *)
    echo "Uso: $0 [dev|pro|all]"
    echo "  dev  — crea solo dev-cluster"
    echo "  pro  — crea solo pro-cluster"
    echo "  all  — crea ambos clusters (por defecto)"
    exit 1
    ;;
esac

echo ""
echo "Clusters disponibles:"
kind get clusters
echo ""
echo "Siguiente paso: ./scripts/install-cni-metallb.sh <dev|pro>"
