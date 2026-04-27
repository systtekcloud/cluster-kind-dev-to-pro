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
    VAULT_VALUES_FILE="$ROOT_DIR/components/vault/dev/values-vault.yaml"
    VSO_VALUES_FILE="$ROOT_DIR/components/vault/dev/values-vso.yaml"
    ;;
  pro)
    CLUSTER_NAME="pro-cluster"
    VAULT_VALUES_FILE="$ROOT_DIR/components/vault/pro/values-vault.yaml"
    VSO_VALUES_FILE="$ROOT_DIR/components/vault/pro/values-vso.yaml"
    ;;
  *)
    echo "ERROR: Target debe ser 'dev' o 'pro', recibido: '$TARGET'"
    exit 1
    ;;
esac

CONTEXT="kind-${CLUSTER_NAME}"
VAULT_NAMESPACE="vault"
VSO_NAMESPACE="vault-secrets-operator"
VAULT_RELEASE="vault"
VSO_RELEASE="vault-secrets-operator"
VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.32.0}"
VSO_CHART_VERSION="${VSO_CHART_VERSION:-1.3.0}"

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: El cluster '$CLUSTER_NAME' no existe. Ejecuta primero: ./scripts/01-create-clusters.sh $TARGET"
  exit 1
fi

echo ">>> Usando contexto: $CONTEXT"
kubectl config use-context "$CONTEXT" >/dev/null

echo ">>> Configurando repositorio Helm de HashiCorp..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update hashicorp

echo ">>> Instalando Vault $VAULT_CHART_VERSION en namespace $VAULT_NAMESPACE..."
helm upgrade --install "$VAULT_RELEASE" hashicorp/vault \
  --namespace "$VAULT_NAMESPACE" \
  --create-namespace \
  --version "$VAULT_CHART_VERSION" \
  --values "$VAULT_VALUES_FILE" \
  --wait \
  --timeout 5m

echo ">>> Instalando Vault Secrets Operator $VSO_CHART_VERSION en namespace $VSO_NAMESPACE..."
helm upgrade --install "$VSO_RELEASE" hashicorp/vault-secrets-operator \
  --namespace "$VSO_NAMESPACE" \
  --create-namespace \
  --version "$VSO_CHART_VERSION" \
  --values "$VSO_VALUES_FILE" \
  --wait \
  --timeout 5m

echo ">>> Esperando CRDs de VSO..."
kubectl wait --for=condition=established \
  crd/vaultauths.secrets.hashicorp.com \
  crd/vaultstaticsecrets.secrets.hashicorp.com \
  crd/vaultconnections.secrets.hashicorp.com \
  --timeout=120s >/dev/null

kubectl wait --for=condition=Available deployment --all -n "$VSO_NAMESPACE" --timeout=180s >/dev/null

echo ""
echo "OK: Vault + VSO instalados en $CLUSTER_NAME"
echo ""
echo "  Siguientes pasos (manuales):"
echo "    kubectl exec -n vault vault-0 -- vault operator init"
echo "    kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>"
echo ""
echo "  Cuando Vault este activo, ejecuta:"
echo "    ./scripts/05-seed-vault.sh $TARGET"
