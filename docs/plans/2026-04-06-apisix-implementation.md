# APISIX Installation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Install APISIX as north-south ingress controller in kind clusters dev/pro, verify MetalLB IP assignment, and provide a working httpbin demo with rate limiting.

**Architecture:** APISIX runs in namespace `ingress-apisix` (Istio sidecar injection disabled). Demo apps live in `demo-apis` namespace. APISIX gets a LoadBalancer IP from MetalLB; ApisixRoute CRDs in `demo-apis` route traffic to httpbin.

**Tech Stack:** Helm 3, APISIX chart (`https://charts.apiseven.com`), ApisixRoute/ApisixUpstream CRDs v2, kubectl, kind.

---

## Context

- Repo root: `cluster-kind-dev-to-prod/`
- Existing scripts follow the pattern in `scripts/install-cni-metallb.sh`: `SCRIPT_DIR`, `ROOT_DIR`, `set -euo pipefail`, `kind get clusters` guard, `>>> ` prefix for output
- Existing values file: `components/apisix/apisix-values/values-apisix.yaml` — has one bug (wrong namespace in endpoint, see Task 1)
- Existing CRD manifests: `components/ingress/apisix/crds/httpbin/httpbin-route.yaml` and `httpbin-upstream.yaml` — namespace `demo-apis`, already correct

---

### Task 1: Fix namespace bug in values-apisix.yaml

**Files:**
- Modify: `components/apisix/apisix-values/values-apisix.yaml:51`

**Context:**

The ingress-controller embedded in the APISIX chart connects to the admin API via an internal service URL. The Helm release name is `apisix` and it is installed in namespace `ingress-apisix`, so the admin service is `apisix-admin.ingress-apisix.svc.cluster.local`. The current value incorrectly references `apisix-ingress` (transposed).

**Step 1: Open the file and locate line 51**

```
components/apisix/apisix-values/values-apisix.yaml
```

Current content of the `gatewayProxy.controlPlane.endpoints` block (lines 49-51):
```yaml
    controlPlane:
      endpoints:
        - http://apisix-admin.apisix-ingress.svc.cluster.local:9180
```

**Step 2: Apply the fix**

Replace line 51:
```yaml
        - http://apisix-admin.ingress-apisix.svc.cluster.local:9180
```

Full resulting block:
```yaml
    controlPlane:
      endpoints:
        - http://apisix-admin.ingress-apisix.svc.cluster.local:9180
      auth:
        type: AdminKey
        adminKey:
          value: edd1c9f034335f136f87ad84b625c8f1
```

**Step 3: Verify the file looks correct**

Run:
```bash
grep -n "apisix-admin" components/apisix/apisix-values/values-apisix.yaml
```
Expected output:
```
51:        - http://apisix-admin.ingress-apisix.svc.cluster.local:9180
```

**Step 4: Commit**

```bash
git add components/apisix/apisix-values/values-apisix.yaml
git commit -m "fix: correct namespace in apisix admin endpoint (apisix-ingress → ingress-apisix)"
```

---

### Task 2: Create scripts/install-apisix.sh

**Files:**
- Create: `scripts/install-apisix.sh`

**Context:**

Follow the exact same structure as `scripts/install-cni-metallb.sh`:
- `SCRIPT_DIR` / `ROOT_DIR` for relative paths
- Guard: `kind get clusters | grep -q "^${CLUSTER_NAME}$"`
- Output prefix: `>>> `
- `set -euo pipefail`

The values file lives at `$ROOT_DIR/components/apisix/apisix-values/values-apisix.yaml`.

Helm release name must be `apisix` (not `apisix-ingress`) so that the admin service is named `apisix-admin` — matching the endpoint in values.

**Step 1: Verify syntax before writing**

After writing the file, run:
```bash
bash -n scripts/install-apisix.sh
```
Expected: no output (no errors).

**Step 2: Write the script**

```bash
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
```

**Step 3: Make executable and verify syntax**

```bash
chmod +x scripts/install-apisix.sh
bash -n scripts/install-apisix.sh
```
Expected: no output.

**Step 4: Commit**

```bash
git add scripts/install-apisix.sh
git commit -m "feat: add install-apisix.sh for APISIX ingress controller deployment"
```

---

### Task 3: Create httpbin demo Deployment + Service

**Files:**
- Create: `components/ingress/apisix/crds/httpbin/httpbin-deploy.yaml`

**Context:**

httpbin is a simple HTTP testing service (image: `kennethreitz/httpbin`). It must live in namespace `demo-apis` to match the existing `httpbin-route.yaml` and `httpbin-upstream.yaml` which already reference `namespace: demo-apis`.

The Service name must be `httpbin` (port 80) — the existing `ApisixRoute` backend references `serviceName: httpbin, servicePort: 80`.

**Step 1: Check the existing route references the correct service**

```bash
grep -A5 "backends" components/ingress/apisix/crds/httpbin/httpbin-route.yaml
```
Expected:
```yaml
      backends:
        - serviceName: httpbin
          servicePort: 80
```

**Step 2: Write the manifest**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: demo-apis
  labels:
    istio-injection: disabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: demo-apis
  labels:
    app: httpbin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
        - name: httpbin
          image: kennethreitz/httpbin
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: demo-apis
spec:
  selector:
    app: httpbin
  ports:
    - port: 80
      targetPort: 80
```

**Step 3: Verify YAML syntax**

```bash
kubectl apply --dry-run=client -f components/ingress/apisix/crds/httpbin/httpbin-deploy.yaml
```
Expected:
```
namespace/demo-apis configured (dry run)
deployment.apps/httpbin created (dry run)
service/httpbin created (dry run)
```

> Note: `kubectl apply --dry-run=client` validates YAML structure without connecting to a cluster. It works even without a running cluster.

**Step 4: Commit**

```bash
git add components/ingress/apisix/crds/httpbin/httpbin-deploy.yaml
git commit -m "feat: add httpbin Deployment and Service for APISIX demo (demo-apis namespace)"
```

---

## Verification (manual, after cluster is running)

Once a cluster exists with CNI + MetalLB installed, run:

```bash
# 1. Instalar APISIX
./scripts/install-apisix.sh dev

# 2. Desplegar httpbin + CRDs de APISIX
kubectl apply -f components/ingress/apisix/crds/httpbin/

# 3. Obtener la IP externa
EXTERNAL_IP=$(kubectl get svc apisix-gateway -n ingress-apisix \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 4. Probar httpbin via APISIX (debería devolver JSON con headers)
curl -s -H "Host: httpbin.local" http://${EXTERNAL_IP}/get | jq .

# 5. Verificar rate limiting (tras 5 requests en 60s, debe devolver 429)
for i in {1..6}; do
  echo "Request $i:"
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: httpbin.local" http://${EXTERNAL_IP}/get
done
```

Expected: first 5 → `200`, request 6 → `429`.
