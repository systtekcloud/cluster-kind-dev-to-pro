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
  dev) CLUSTER_NAME="dev-cluster" ;;
  pro) CLUSTER_NAME="pro-cluster" ;;
  *)
    echo "ERROR: Target debe ser 'dev' o 'pro', recibido: '$TARGET'"
    exit 1
    ;;
esac

CONTEXT="kind-${CLUSTER_NAME}"
VAULT_NAMESPACE="vault"
VAULT_POD="vault-0"
VAULT_ADDR="http://127.0.0.1:8200"
POLICY_FILE="$ROOT_DIR/components/vault/setup/policy-keycloak.hcl"

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: El cluster '$CLUSTER_NAME' no existe."
  exit 1
fi

echo ">>> Usando contexto: $CONTEXT"
kubectl config use-context "$CONTEXT" >/dev/null

echo ">>> Comprobando que Vault esta activo y desellado..."
VAULT_STATUS="$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" vault status 2>/dev/null || true)"

if ! echo "$VAULT_STATUS" | grep -q "^Sealed.*false"; then
  echo "ERROR: Vault esta sellado o no responde. Haz el unseal primero:"
  echo "  kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>"
  exit 1
fi

# Root token: via env var o prompt interactivo
if [[ -z "${VAULT_ROOT_TOKEN:-}" ]]; then
  read -r -s -p "Vault Root Token: " VAULT_ROOT_TOKEN
  echo
fi

if [[ -z "$VAULT_ROOT_TOKEN" ]]; then
  echo "ERROR: Root token no puede estar vacio."
  exit 1
fi

vault_cmd() {
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_ROOT_TOKEN" "$@"
}

# ─── Configurar Vault (idempotente) ───────────────────────────────────────────

echo ">>> Habilitando KV v2 en secret/..."
vault_cmd sh -c 'vault secrets list | grep -q "^secret/" || vault secrets enable -path=secret kv-v2 >/dev/null'

echo ">>> Configurando Kubernetes auth..."
vault_cmd sh -c '
  vault auth list | grep -q "^kubernetes/" || vault auth enable kubernetes >/dev/null
  vault write auth/kubernetes/config \
    kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}" >/dev/null
'

echo ">>> Aplicando policy keycloak..."
kubectl exec -i -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
  vault policy write keycloak - <"$POLICY_FILE" >/dev/null

echo ">>> Creando role keycloak..."
vault_cmd vault write auth/kubernetes/role/keycloak \
  bound_service_account_names=default \
  bound_service_account_namespaces=keycloak \
  policies=keycloak \
  ttl=24h >/dev/null

# ─── Keycloak ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Secretos de Keycloak ==="
read -r -s -p "Keycloak DB password: " KEYCLOAK_DB_PASSWORD
echo
read -r -s -p "Keycloak admin password: " KEYCLOAK_ADMIN_PASSWORD
echo

if [[ -z "$KEYCLOAK_DB_PASSWORD" || -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
  echo "ERROR: Los passwords de Keycloak no pueden estar vacios."
  exit 1
fi

kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
  TARGET="$TARGET" \
  KEYCLOAK_DB_PASSWORD="$KEYCLOAK_DB_PASSWORD" \
  KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" \
  sh -c 'vault kv put secret/${TARGET}/keycloak \
    db_password="${KEYCLOAK_DB_PASSWORD}" \
    admin_password="${KEYCLOAK_ADMIN_PASSWORD}"' >/dev/null

echo "OK: Keycloak -> secret/$TARGET/keycloak"

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
  echo "ERROR: Los campos de MongoDB no pueden estar vacios."
  exit 1
fi

kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
  env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
  TARGET="$TARGET" \
  MONGO_ADMIN_USER="$MONGO_ADMIN_USER" \
  MONGO_ADMIN_PASSWORD="$MONGO_ADMIN_PASSWORD" \
  MONGO_APP_USER="$MONGO_APP_USER" \
  MONGO_APP_PASSWORD="$MONGO_APP_PASSWORD" \
  sh -c '
    vault kv put secret/${TARGET}/mongodb/users/admin \
      username="${MONGO_ADMIN_USER}" \
      password="${MONGO_ADMIN_PASSWORD}"
    vault kv put secret/${TARGET}/mongodb/users/${MONGO_APP_USER} \
      username="${MONGO_APP_USER}" \
      password="${MONGO_APP_PASSWORD}"
  ' >/dev/null

echo "OK: MongoDB  -> secret/$TARGET/mongodb/users/admin"
echo "OK: MongoDB  -> secret/$TARGET/mongodb/users/$MONGO_APP_USER"

# ─── Resumen ──────────────────────────────────────────────────────────────────

echo ""
echo "OK: Vault configurado y secretos sembrados en $CLUSTER_NAME"
echo ""
echo "  secret/$TARGET/keycloak          (db_password, admin_password)"
echo "  secret/$TARGET/mongodb/users/admin"
echo "  secret/$TARGET/mongodb/users/$MONGO_APP_USER"
