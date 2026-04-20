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
    HA_MODE=false
    ;;
  pro)
    CLUSTER_NAME="pro-cluster"
    VAULT_VALUES_FILE="$ROOT_DIR/components/vault/pro/values-vault.yaml"
    VSO_VALUES_FILE="$ROOT_DIR/components/vault/pro/values-vso.yaml"
    HA_MODE=true
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
VAULT_POD="vault-0"
VAULT_ADDR="http://127.0.0.1:8200"
VAULT_CHART_VERSION="${VAULT_CHART_VERSION:-0.32.0}"
VSO_CHART_VERSION="${VSO_CHART_VERSION:-1.3.0}"
SKIP_VAULT_SEED="${SKIP_VAULT_SEED:-0}"

POLICY_FILE="$ROOT_DIR/components/vault/setup/policy-keycloak.hcl"
SEED_SCRIPT="$ROOT_DIR/components/vault/setup/seed-secrets.sh"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: No se encuentra el fichero requerido: $path"
    exit 1
  fi
}

vault_status() {
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" vault status 2>/dev/null || true
}

vault_secret_value() {
  local key="$1"
  kubectl get secret vault-init-keys -n "$VAULT_NAMESPACE" -o "jsonpath={.data.${key}}" | base64 -d
}

wait_for_vault() {
  echo ">>> Esperando a que Vault esté ready..."
  kubectl rollout status statefulset/"$VAULT_RELEASE" -n "$VAULT_NAMESPACE" --timeout=5m

  if [[ "$HA_MODE" == "true" ]]; then
    for pod in vault-0 vault-1 vault-2; do
      kubectl wait --for=condition=Ready pod/"$pod" -n "$VAULT_NAMESPACE" --timeout=180s >/dev/null
    done
  else
    kubectl wait --for=condition=Ready pod/"$VAULT_POD" -n "$VAULT_NAMESPACE" --timeout=180s >/dev/null
  fi
}

store_init_material() {
  local root_token="$1"
  local unseal_key="$2"
  local tmpdir
  tmpdir="$(mktemp -d)"

  cat >"$tmpdir/init.json" <<EOF
{"root_token":"$root_token","unseal_keys_b64":["$unseal_key"],"unseal_threshold":1}
EOF
  printf '%s' "$root_token" >"$tmpdir/root_token"
  printf '%s' "$unseal_key" >"$tmpdir/unseal_key"

  kubectl create secret generic vault-init-keys \
    -n "$VAULT_NAMESPACE" \
    --from-file=init.json="$tmpdir/init.json" \
    --from-file=root_token="$tmpdir/root_token" \
    --from-file=unseal_key="$tmpdir/unseal_key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  rm -rf "$tmpdir"
}

# Para HA pro: une vault-1 y vault-2 al cluster Raft y los desella
join_raft_peers() {
  local unseal_key="$1"
  for pod in vault-1 vault-2; do
    if ! kubectl get pod "$pod" -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
      echo "WARN: Pod $pod no encontrado, saltando..."
      continue
    fi

    local peer_status initialized sealed
    peer_status="$(kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- \
      env VAULT_ADDR="$VAULT_ADDR" vault status 2>/dev/null || true)"
    initialized="$(awk '/Initialized/ {print $2}' <<<"$peer_status")"
    sealed="$(awk '/Sealed/ {print $2}' <<<"$peer_status")"

    if [[ "$initialized" == "false" ]]; then
      echo ">>> Uniendo $pod al cluster Raft de vault-0..."
      kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- \
        env VAULT_ADDR="$VAULT_ADDR" \
        vault operator raft join http://vault-0.vault-internal:8200 >/dev/null
      # Re-leer estado tras el join
      peer_status="$(kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- \
        env VAULT_ADDR="$VAULT_ADDR" vault status 2>/dev/null || true)"
      sealed="$(awk '/Sealed/ {print $2}' <<<"$peer_status")"
    else
      echo ">>> $pod ya está unido al cluster Raft."
    fi

    if [[ "$sealed" == "true" ]]; then
      echo ">>> Desellando $pod..."
      kubectl exec -n "$VAULT_NAMESPACE" "$pod" -- \
        env VAULT_ADDR="$VAULT_ADDR" \
        vault operator unseal "$unseal_key" >/dev/null
    else
      echo ">>> $pod ya está desellado."
    fi
  done
}

initialize_or_unseal_vault() {
  local status_output initialized sealed init_output unseal_key root_token

  status_output="$(vault_status)"
  initialized="$(awk '/Initialized/ {print $2}' <<<"$status_output")"
  sealed="$(awk '/Sealed/ {print $2}' <<<"$status_output")"

  if [[ "$initialized" == "false" ]]; then
    echo ">>> Inicializando Vault por primera vez..."
    init_output="$(kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
      env VAULT_ADDR="$VAULT_ADDR" \
      vault operator init -key-shares=1 -key-threshold=1)"

    unseal_key="$(awk -F': ' '/Unseal Key 1/ {print $2}' <<<"$init_output")"
    root_token="$(awk -F': ' '/Initial Root Token/ {print $2}' <<<"$init_output")"

    if [[ -z "$unseal_key" || -z "$root_token" ]]; then
      echo "ERROR: No se pudieron extraer el unseal key y root token desde vault operator init."
      exit 1
    fi

    store_init_material "$root_token" "$unseal_key"

    echo ">>> Desellando vault-0..."
    kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
      env VAULT_ADDR="$VAULT_ADDR" \
      vault operator unseal "$unseal_key" >/dev/null

    if [[ "$HA_MODE" == "true" ]]; then
      join_raft_peers "$unseal_key"
    fi
    return
  fi

  if ! kubectl get secret vault-init-keys -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
    echo "ERROR: Vault ya está inicializado, pero falta el Secret vault-init-keys en namespace $VAULT_NAMESPACE."
    echo "       No es seguro continuar sin el material de bootstrap."
    exit 1
  fi

  unseal_key="$(vault_secret_value unseal_key)"

  if [[ "$sealed" == "true" ]]; then
    echo ">>> Vault ya estaba inicializado. Ejecutando unseal con la clave guardada..."
    kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
      env VAULT_ADDR="$VAULT_ADDR" \
      vault operator unseal "$unseal_key" >/dev/null
  else
    echo ">>> vault-0 ya estaba inicializado y desellado."
  fi

  if [[ "$HA_MODE" == "true" ]]; then
    join_raft_peers "$unseal_key"
  fi
}

configure_vault() {
  local root_token
  root_token="$(vault_secret_value root_token)"

  echo ">>> Habilitando motor KV v2 en secret/..."
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$root_token" \
    sh -ec '
      vault secrets list | awk "{print \$1}" | grep -q "^secret/$" || \
      vault secrets enable -path=secret kv-v2 >/dev/null
    '

  echo ">>> Configurando auth method de Kubernetes..."
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$root_token" \
    sh -ec '
      vault auth list | awk "{print \$1}" | grep -q "^kubernetes/$" || \
      vault auth enable kubernetes >/dev/null

      vault write auth/kubernetes/config \
        kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}" >/dev/null
    '

  echo ">>> Aplicando policy keycloak..."
  kubectl exec -i -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$root_token" \
    vault policy write keycloak - <"$POLICY_FILE" >/dev/null

  echo ">>> Creando/actualizando role keycloak..."
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$root_token" \
    vault write auth/kubernetes/role/keycloak \
      bound_service_account_names=default \
      bound_service_account_namespaces=keycloak \
      policies=keycloak \
      ttl=24h >/dev/null
}

install_vso() {
  echo ">>> Instalando Vault Secrets Operator en namespace $VSO_NAMESPACE..."
  helm upgrade --install "$VSO_RELEASE" hashicorp/vault-secrets-operator \
    --namespace "$VSO_NAMESPACE" \
    --create-namespace \
    --version "$VSO_CHART_VERSION" \
    --values "$VSO_VALUES_FILE" \
    --wait \
    --timeout 5m

  echo ">>> Esperando CRDs principales de VSO..."
  kubectl wait --for=condition=established \
    crd/vaultauths.secrets.hashicorp.com \
    crd/vaultstaticsecrets.secrets.hashicorp.com \
    crd/vaultconnections.secrets.hashicorp.com \
    --timeout=120s >/dev/null

  kubectl wait --for=condition=Available deployment --all -n "$VSO_NAMESPACE" --timeout=180s >/dev/null
}

# ─── Pre-flight checks ────────────────────────────────────────────────────────

require_file "$VAULT_VALUES_FILE"
require_file "$VSO_VALUES_FILE"
require_file "$POLICY_FILE"
require_file "$SEED_SCRIPT"

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: El cluster '$CLUSTER_NAME' no existe. Ejecútalo primero con: ./scripts/01-create-clusters.sh $TARGET"
  exit 1
fi

echo ">>> Usando contexto: $CONTEXT"
kubectl config use-context "$CONTEXT" >/dev/null

# ─── Helm repo ────────────────────────────────────────────────────────────────

echo ">>> Configurando repositorio Helm de HashiCorp..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update hashicorp

# ─── Vault ────────────────────────────────────────────────────────────────────

echo ">>> Instalando Vault $VAULT_CHART_VERSION en namespace $VAULT_NAMESPACE..."
helm upgrade --install "$VAULT_RELEASE" hashicorp/vault \
  --namespace "$VAULT_NAMESPACE" \
  --create-namespace \
  --version "$VAULT_CHART_VERSION" \
  --values "$VAULT_VALUES_FILE" \
  --wait \
  --timeout 5m

wait_for_vault
initialize_or_unseal_vault
wait_for_vault
configure_vault
install_vso

# ─── Seed ─────────────────────────────────────────────────────────────────────

if [[ "$SKIP_VAULT_SEED" == "1" ]]; then
  echo ">>> SKIP_VAULT_SEED=1 detectado. Saltando siembra interactiva de secretos."
else
  "$SEED_SCRIPT" "$TARGET"
fi

# ─── Resumen ──────────────────────────────────────────────────────────────────

echo ""
echo "OK: Vault + VSO bootstrap completado en $CLUSTER_NAME"
echo ""
echo "  Vault chart version: $VAULT_CHART_VERSION"
echo "  VSO chart version:   $VSO_CHART_VERSION"
echo "  Vault namespace:     $VAULT_NAMESPACE"
echo "  VSO namespace:       $VSO_NAMESPACE"
echo "  HA mode:             $HA_MODE"
echo ""
echo "  Material bootstrap:"
echo "    kubectl get secret vault-init-keys -n $VAULT_NAMESPACE -o yaml"
