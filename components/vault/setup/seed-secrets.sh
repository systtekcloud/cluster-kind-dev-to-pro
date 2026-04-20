#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

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
VAULT_NAMESPACE="vault"
VAULT_SECRET_NAME="vault-init-keys"
VAULT_ADDR="http://127.0.0.1:8200"

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: El cluster '$CLUSTER_NAME' no existe. Ejecútalo primero con: ./scripts/05-install-vault.sh $TARGET"
  exit 1
fi

echo ">>> Usando contexto: $CONTEXT"
kubectl config use-context "$CONTEXT" >/dev/null

if ! kubectl get secret "$VAULT_SECRET_NAME" -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: No existe el Secret ${VAULT_SECRET_NAME} en namespace ${VAULT_NAMESPACE}."
  echo "       Ejecuta primero: ./scripts/05-install-vault.sh $TARGET"
  exit 1
fi

echo ">>> Esperando a que Vault esté ready..."
kubectl wait --for=condition=Ready pod/vault-0 -n "$VAULT_NAMESPACE" --timeout=180s >/dev/null

VAULT_ROOT_TOKEN="$(kubectl get secret "$VAULT_SECRET_NAME" -n "$VAULT_NAMESPACE" \
  -o jsonpath='{.data.root_token}' | base64 -d)"

# ─── Keycloak ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Secretos de Keycloak ==="
read -r -s -p "Keycloak DB password: " KEYCLOAK_DB_PASSWORD
echo
read -r -s -p "Keycloak admin password: " KEYCLOAK_ADMIN_PASSWORD
echo

if [[ -z "$KEYCLOAK_DB_PASSWORD" || -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
  echo "ERROR: Los passwords de Keycloak no pueden estar vacíos."
  exit 1
fi

echo ">>> Sembrando secretos en Vault (secret/$TARGET/keycloak)..."
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- \
  env \
    VAULT_ADDR="$VAULT_ADDR" \
    VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
    KEYCLOAK_DB_PASSWORD="$KEYCLOAK_DB_PASSWORD" \
    KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" \
    TARGET="$TARGET" \
  sh -ec '
    vault kv put secret/${TARGET}/keycloak \
      db_password="${KEYCLOAK_DB_PASSWORD}" \
      admin_password="${KEYCLOAK_ADMIN_PASSWORD}" \
      admin-password="${KEYCLOAK_ADMIN_PASSWORD}"
  ' >/dev/null

kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_ROOT_TOKEN" TARGET="$TARGET" \
  sh -ec 'vault kv get secret/${TARGET}/keycloak' >/dev/null

echo "OK: Keycloak → secret/$TARGET/keycloak"

# ─── MongoDB ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Secretos de MongoDB ==="
read -r -p "MongoDB admin username [root]: " MONGO_ADMIN_USER
MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-root}"
read -r -s -p "MongoDB admin password: " MONGO_ADMIN_PASSWORD
echo
read -r -p "MongoDB app username: " MONGO_APP_USER
read -r -s -p "MongoDB app password: " MONGO_APP_PASSWORD
echo

if [[ -z "$MONGO_ADMIN_PASSWORD" || -z "$MONGO_APP_USER" || -z "$MONGO_APP_PASSWORD" ]]; then
  echo "ERROR: Los campos de MongoDB no pueden estar vacíos."
  exit 1
fi

echo ">>> Sembrando secretos en Vault (secret/$TARGET/mongodb/users/...)..."
kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- \
  env \
    VAULT_ADDR="$VAULT_ADDR" \
    VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
    MONGO_ADMIN_USER="$MONGO_ADMIN_USER" \
    MONGO_ADMIN_PASSWORD="$MONGO_ADMIN_PASSWORD" \
    MONGO_APP_USER="$MONGO_APP_USER" \
    MONGO_APP_PASSWORD="$MONGO_APP_PASSWORD" \
    TARGET="$TARGET" \
  sh -ec '
    vault kv put secret/${TARGET}/mongodb/users/admin \
      username="${MONGO_ADMIN_USER}" \
      password="${MONGO_ADMIN_PASSWORD}"

    vault kv put secret/${TARGET}/mongodb/users/${MONGO_APP_USER} \
      username="${MONGO_APP_USER}" \
      password="${MONGO_APP_PASSWORD}"
  ' >/dev/null

echo "OK: MongoDB  → secret/$TARGET/mongodb/users/admin"
echo "OK: MongoDB  → secret/$TARGET/mongodb/users/$MONGO_APP_USER"

# ─── Resumen ──────────────────────────────────────────────────────────────────

echo ""
echo "OK: Secretos sembrados en Vault ($CLUSTER_NAME)"
echo ""
echo "  Keycloak:"
echo "    secret/$TARGET/keycloak"
echo "      db_password, admin_password, admin-password"
echo ""
echo "  MongoDB:"
echo "    secret/$TARGET/mongodb/users/admin"
echo "    secret/$TARGET/mongodb/users/$MONGO_APP_USER"
