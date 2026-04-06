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
    ;;
  pro)
    CLUSTER_NAME="pro-cluster"
    ;;
  *)
    echo "ERROR: Target debe ser 'dev' o 'pro', recibido: '$TARGET'"
    exit 1
    ;;
esac

CONTEXT="kind-${CLUSTER_NAME}"
VALUES_FILE="$ROOT_DIR/components/apisix/apisix-values/values-apisix.yaml"
NAMESPACE="ingress-apisix"

# Verificar que el cluster existe
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: El cluster '$CLUSTER_NAME' no existe. Ejecútalo primero con: ./scripts/create-clusters.sh $TARGET"
  exit 1
fi

# Verificar que el values file existe
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "ERROR: No se encuentra el fichero de valores: $VALUES_FILE"
  exit 1
fi

echo ">>> Usando contexto: $CONTEXT"
kubectl config use-context "$CONTEXT"

# ─── Namespace ────────────────────────────────────────────────────────────────

echo ">>> Creando namespace $NAMESPACE (istio-injection: disabled)..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | kubectl apply -f -

# Deshabilitar sidecar injection de Istio en este namespace (cuando Istio se instale)
kubectl label namespace "$NAMESPACE" istio-injection=disabled --overwrite

# ─── Helm repo ────────────────────────────────────────────────────────────────

echo ">>> Configurando repositorio Helm de APISIX..."
helm repo add apisix https://charts.apiseven.com 2>/dev/null || true
helm repo update apisix

# ─── APISIX ───────────────────────────────────────────────────────────────────

echo ">>> Instalando APISIX en namespace $NAMESPACE..."
helm upgrade --install apisix apisix/apisix \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 5m

# ─── Verificación MetalLB ─────────────────────────────────────────────────────

echo ">>> Esperando a que MetalLB asigne EXTERNAL-IP al LoadBalancer de APISIX..."
TIMEOUT=120
ELAPSED=0
EXTERNAL_IP=""

while [[ -z "$EXTERNAL_IP" && $ELAPSED -lt $TIMEOUT ]]; do
  EXTERNAL_IP=$(kubectl get svc apisix-gateway \
    -n "$NAMESPACE" \
    --context "$CONTEXT" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -z "$EXTERNAL_IP" ]]; then
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... esperando IP ($ELAPSED/${TIMEOUT}s)"
  fi
done

if [[ -z "$EXTERNAL_IP" ]]; then
  echo "WARN: No se asignó EXTERNAL-IP en ${TIMEOUT}s. Verifica MetalLB con: kubectl get svc -n $NAMESPACE"
else
  echo ""
  echo "OK: APISIX instalado en $CLUSTER_NAME"
  echo ""
  echo "  EXTERNAL-IP asignada: $EXTERNAL_IP"
  echo ""
  echo "  Prueba de conectividad:"
  echo "    curl -i http://${EXTERNAL_IP}/"
  echo ""
  echo "  Para desplegar httpbin de demo:"
  echo "    kubectl apply -f components/ingress/apisix/crds/httpbin/"
  echo "    curl -H 'Host: httpbin.local' http://${EXTERNAL_IP}/get"
fi
