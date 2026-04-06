#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "Uso: $0 <dev|pro>"
  exit 1
fi

case "$TARGET" in
  dev)
    CLUSTER_NAME="dev-cluster"
    METALLB_POOL="$ROOT_DIR/dev/kind/metallb-ippool.yaml"
    ;;
  pro)
    CLUSTER_NAME="pro-cluster"
    METALLB_POOL="$ROOT_DIR/pro/kind/metallb-ippool.yaml"
    ;;
  *)
    echo "ERROR: Target debe ser 'dev' o 'pro', recibido: '$TARGET'"
    exit 1
    ;;
esac

CONTEXT="kind-${CLUSTER_NAME}"

# Verificar que el cluster existe
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: El cluster '$CLUSTER_NAME' no existe. Ejecútalo primero con: ./scripts/create-clusters.sh $TARGET"
  exit 1
fi

echo ">>> Usando contexto: $CONTEXT"
kubectl config use-context "$CONTEXT"

# ─── Cilium ───────────────────────────────────────────────────────────────────

install_cilium_cli() {
  if command -v cilium &>/dev/null; then
    echo "INFO: Cilium CLI ya instalado ($(cilium version --client 2>/dev/null | head -1))"
    return
  fi

  echo ">>> Instalando Cilium CLI..."
  local OS
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  local ARCH
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  local CILIUM_VERSION
  CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)

  curl -L --fail \
    "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_VERSION}/cilium-${OS}-${ARCH}.tar.gz" \
    | tar xz -C /tmp

  sudo mv /tmp/cilium /usr/local/bin/cilium
  echo ">>> Cilium CLI instalado: $(cilium version --client 2>/dev/null | head -1)"
}

install_cilium_cli

echo ">>> Instalando Cilium en $CLUSTER_NAME..."
# kubeProxyReplacement=true: Cilium reemplaza kube-proxy completamente
# k8sServiceHost/Port: dirección del API server dentro del cluster kind
cilium install \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${CLUSTER_NAME}-control-plane" \
  --set k8sServicePort=6443

echo ">>> Esperando a que Cilium esté ready..."
cilium status --wait

# ─── MetalLB ──────────────────────────────────────────────────────────────────

echo ">>> Instalando MetalLB via Helm..."
helm repo add metallb https://metallb.github.io/metallb 2>/dev/null || helm repo update metallb
helm repo update

helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --wait

echo ">>> Esperando a que los CRDs de MetalLB estén disponibles..."
kubectl wait --for=condition=established \
  crd/ipaddresspools.metallb.io \
  crd/l2advertisements.metallb.io \
  --timeout=60s

# Pausa para que el webhook de MetalLB esté listo antes de aplicar recursos
sleep 5

echo ">>> Aplicando pool de IPs MetalLB: $METALLB_POOL"
kubectl apply -f "$METALLB_POOL"

# ─── Verificación ─────────────────────────────────────────────────────────────

echo ""
echo ">>> Estado final del cluster $CLUSTER_NAME:"
echo ""
echo "--- Nodos ---"
kubectl get nodes -o wide

echo ""
echo "--- Cilium ---"
cilium status

echo ""
echo "--- MetalLB ---"
kubectl get pods -n metallb-system

echo ""
echo "OK: CNI + MetalLB instalados en $CLUSTER_NAME"
