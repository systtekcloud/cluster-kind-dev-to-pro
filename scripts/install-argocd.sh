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
    VALUES_FILE="$ROOT_DIR/components/argocd/values-local.yaml"
    ;;
  pro)
    CLUSTER_NAME="pro-cluster"
    VALUES_FILE="$ROOT_DIR/components/argocd/values-ha.yaml"
    ;;
  *)
    echo "ERROR: Target debe ser 'dev' o 'pro', recibido: '$TARGET'"
    exit 1
    ;;
esac

CONTEXT="kind-${CLUSTER_NAME}"
NAMESPACE="argocd"

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

# ─── Helm repo ────────────────────────────────────────────────────────────────

echo ">>> Configurando repositorio Helm de Argo..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

# ─── ArgoCD ───────────────────────────────────────────────────────────────────

echo ">>> Instalando ArgoCD en namespace $NAMESPACE..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 5m

# ─── Verificación MetalLB ─────────────────────────────────────────────────────

echo ">>> Esperando a que MetalLB asigne EXTERNAL-IP al LoadBalancer de ArgoCD..."
TIMEOUT=120
ELAPSED=0
EXTERNAL_IP=""

while [[ -z "$EXTERNAL_IP" && $ELAPSED -lt $TIMEOUT ]]; do
  EXTERNAL_IP=$(kubectl get svc argocd-server \
    -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -z "$EXTERNAL_IP" ]]; then
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... esperando IP ($ELAPSED/${TIMEOUT}s)"
  fi
done

if [[ -z "$EXTERNAL_IP" ]]; then
  echo "ERROR: No se asignó EXTERNAL-IP en ${TIMEOUT}s. Verifica MetalLB con: kubectl get svc -n $NAMESPACE --context $CONTEXT"
  exit 1
fi

ADMIN_PASSWORD=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(no disponible aún)")

echo ""
echo "OK: ArgoCD instalado en $CLUSTER_NAME"
echo ""
echo "  EXTERNAL-IP asignada: $EXTERNAL_IP"
echo "  URL de acceso:        http://${EXTERNAL_IP}"
echo "  Usuario:              admin"
echo "  Contraseña inicial:   ${ADMIN_PASSWORD}"
echo ""
echo "  Para recuperar la contraseña más tarde:"
echo "    kubectl -n $NAMESPACE get secret argocd-initial-admin-secret \\"
echo "      -o jsonpath=\"{.data.password}\" | base64 -d"
