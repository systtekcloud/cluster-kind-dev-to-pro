# Kind Clusters dev/pro — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Revisar y completar la configuración de dos clusters kind (dev/pro) con Cilium + MetalLB, incluyendo scripts de gestión y README.

**Architecture:** Dos clusters kind independientes con CIDRs separados, listos para Istio multicluster futuro. Cilium como CNI (reemplaza kube-proxy), MetalLB en modo L2 para servicios LoadBalancer. Scripts bash en `scripts/` para gestión del ciclo de vida.

**Tech Stack:** kind, kubectl, Cilium CLI, Helm, MetalLB, bash

---

### Task 1: Actualizar dev-cluster.yaml con comentarios

**Files:**
- Modify: `dev/kind/dev-cluster.yaml`

**Step 1: Reemplazar el contenido con versión comentada**

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: dev-cluster
# Runtime APIs necesarias para admission webhooks y autenticación
runtimeConfig:
  "authentication.k8s.io/v1beta1": true
  "admissionregistration.k8s.io/v1beta1": true
networking:
  apiServerAddress: "0.0.0.0"
  # CNI desactivado: se instala Cilium manualmente post-creación
  disableDefaultCNI: true
  apiServerPort: 6450
  # CIDRs separados de pro (10.30/10.40) para facilitar Istio multicluster futuro
  podSubnet: "10.10.0.0/16"
  serviceSubnet: "10.20.0.0/16"
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
            extraArgs:
              enable-admission-plugins: NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook
    extraPortMappings:
      # etcd expuesto para acceso directo desde host (debugging, backup)
      - containerPort: 2379
        hostPort: 2090
    extraMounts:
      # Requerido por Falco para AppArmor (labs CKS)
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      # Requerido por Falco para acceso a dispositivos del kernel (labs CKS)
      - hostPath: /dev
        containerPath: /dev
      # Requerido por Falco con Docker runtime (labs CKS)
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
  - role: worker
    extraPortMappings:
      # Fallback NodePort para HTTP cuando MetalLB IPs no son accesibles (VPN/red diferente)
      - containerPort: 80
        hostPort: 9090
      # Fallback NodePort para HTTPS
      - containerPort: 443
        hostPort: 8440
      # Puerto reservado para bastion/jump pod con servidor SSH
      - containerPort: 2222
        hostPort: 2030
    extraMounts:
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      - hostPath: /dev
        containerPath: /dev
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
  - role: worker
    extraPortMappings:
      - containerPort: 80
        hostPort: 9091
      - containerPort: 443
        hostPort: 8441
      - containerPort: 2222
        hostPort: 2031
    extraMounts:
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      - hostPath: /dev
        containerPath: /dev
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
  - role: worker
    extraPortMappings:
      - containerPort: 80
        hostPort: 9092
      - containerPort: 443
        hostPort: 8442
      - containerPort: 2222
        hostPort: 2032
    extraMounts:
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      - hostPath: /dev
        containerPath: /dev
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
```

**Step 2: Verificar YAML válido**

```bash
python3 -c "import yaml; yaml.safe_load(open('dev/kind/dev-cluster.yaml'))" && echo "OK"
```
Expected: `OK`

**Step 3: Commit**

```bash
git add dev/kind/dev-cluster.yaml
git commit -m "docs: add explanatory comments to dev-cluster.yaml"
```

---

### Task 2: Crear pro-cluster.yaml (renombrar + corregir typo + comentar)

**Files:**
- Delete: `prod/kind/prod-cluster.yaml`
- Create: `pro/kind/pro-cluster.yaml`
- Note: el directorio cambia de `prod/` a `pro/`

**Step 1: Crear directorio pro/kind/**

```bash
mkdir -p pro/kind
```

**Step 2: Crear pro/kind/pro-cluster.yaml**

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: pro-cluster
# Runtime APIs necesarias para admission webhooks y autenticación
runtimeConfig:
  "authentication.k8s.io/v1beta1": true
  "admissionregistration.k8s.io/v1beta1": true
networking:
  apiServerAddress: "0.0.0.0"
  # CNI desactivado: se instala Cilium manualmente post-creación
  disableDefaultCNI: true
  apiServerPort: 6451
  # CIDRs separados de dev (10.10/10.20) para facilitar Istio multicluster futuro
  podSubnet: "10.30.0.0/16"
  serviceSubnet: "10.40.0.0/16"
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
            extraArgs:
              enable-admission-plugins: NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook
    extraPortMappings:
      # etcd expuesto para acceso directo desde host (debugging, backup)
      - containerPort: 2379
        hostPort: 2190
    extraMounts:
      # Requerido por Falco para AppArmor (labs CKS)
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      # Requerido por Falco para acceso a dispositivos del kernel (labs CKS)
      - hostPath: /dev
        containerPath: /dev
      # Requerido por Falco con Docker runtime (labs CKS)
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
  - role: worker
    extraPortMappings:
      # Fallback NodePort para HTTP cuando MetalLB IPs no son accesibles (VPN/red diferente)
      - containerPort: 80
        hostPort: 9093
      # Fallback NodePort para HTTPS
      - containerPort: 443
        hostPort: 8450
      # Puerto reservado para bastion/jump pod con servidor SSH
      - containerPort: 2222
        hostPort: 2130
    extraMounts:
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      - hostPath: /dev
        containerPath: /dev
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
  - role: worker
    extraPortMappings:
      - containerPort: 80
        hostPort: 9094
      - containerPort: 443
        hostPort: 8451
      - containerPort: 2222
        hostPort: 2131
    extraMounts:
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      - hostPath: /dev
        containerPath: /dev
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
  - role: worker
    extraPortMappings:
      # Nota: corregido typo del original (9195 → 9095 siguiendo patrón 909x)
      - containerPort: 80
        hostPort: 9095
      - containerPort: 443
        hostPort: 8452
      - containerPort: 2222
        hostPort: 2132
    extraMounts:
      - hostPath: /sys/kernel/security
        containerPath: /sys/kernel/security
      - hostPath: /dev
        containerPath: /dev
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
```

**Step 3: Mover metallb-ippool.yaml al nuevo directorio (ver Task 4)**

Lo haremos en Task 4.

**Step 4: Verificar YAML válido**

```bash
python3 -c "import yaml; yaml.safe_load(open('pro/kind/pro-cluster.yaml'))" && echo "OK"
```
Expected: `OK`

**Step 5: Eliminar directorio prod/ ya obsoleto**

```bash
rm -rf prod/
```

**Step 6: Commit**

```bash
git add pro/kind/pro-cluster.yaml
git rm -r prod/
git commit -m "feat: rename prod → pro cluster, fix hostPort typo (9195→9095), add comments"
```

---

### Task 3: Actualizar metallb-ippool.yaml de dev

**Files:**
- Modify: `dev/kind/metallb-ippool.yaml`

**Step 1: Reemplazar contenido**

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  # Nombre específico de entorno para evitar conflictos si se usa federation futura
  name: dev-pool
  namespace: metallb-system
spec:
  addresses:
    # Rango reservado para dev. Ajustar según subred del bridge de Docker (docker network inspect kind)
    - 172.18.0.120-172.18.0.130
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: dev-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - dev-pool
```

**Step 2: Verificar YAML válido**

```bash
python3 -c "import yaml; list(yaml.safe_load_all(open('dev/kind/metallb-ippool.yaml')))" && echo "OK"
```
Expected: `OK`

**Step 3: Commit**

```bash
git add dev/kind/metallb-ippool.yaml
git commit -m "feat: rename MetalLB resources to dev-pool/dev-l2-advertisement"
```

---

### Task 4: Crear metallb-ippool.yaml de pro

**Files:**
- Create: `pro/kind/metallb-ippool.yaml`

**Step 1: Crear fichero**

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  # Nombre específico de entorno para evitar conflictos si se usa federation futura
  name: pro-pool
  namespace: metallb-system
spec:
  addresses:
    # Rango reservado para pro. Ajustar según subred del bridge de Docker (docker network inspect kind)
    - 172.18.0.131-172.18.0.140
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: pro-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - pro-pool
```

**Step 2: Verificar YAML válido**

```bash
python3 -c "import yaml; list(yaml.safe_load_all(open('pro/kind/metallb-ippool.yaml')))" && echo "OK"
```
Expected: `OK`

**Step 3: Commit**

```bash
git add pro/kind/metallb-ippool.yaml
git commit -m "feat: add pro MetalLB pool config (pro-pool/pro-l2-advertisement)"
```

---

### Task 5: Crear scripts/create-clusters.sh

**Files:**
- Create: `scripts/create-clusters.sh`

**Step 1: Crear el script**

```bash
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
    if ss -tlnp "sport = :$port" 2>/dev/null | grep -q LISTEN; then
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
```

**Step 2: Dar permisos de ejecución**

```bash
chmod +x scripts/create-clusters.sh
```

**Step 3: Verificar sintaxis bash**

```bash
bash -n scripts/create-clusters.sh && echo "OK"
```
Expected: `OK`

**Step 4: Commit**

```bash
git add scripts/create-clusters.sh
git commit -m "feat: add create-clusters.sh with port and Docker checks"
```

---

### Task 6: Crear scripts/install-cni-metallb.sh

**Files:**
- Create: `scripts/install-cni-metallb.sh`

**Step 1: Crear el script**

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
# --set kubeProxyReplacement=true requiere que kube-proxy no esté corriendo
# kind sin CNI no tiene kube-proxy activo, ideal para reemplazo completo
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

# Pequeña pausa para que el webhook de MetalLB esté listo antes de aplicar recursos
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
```

**Step 2: Dar permisos de ejecución**

```bash
chmod +x scripts/install-cni-metallb.sh
```

**Step 3: Verificar sintaxis bash**

```bash
bash -n scripts/install-cni-metallb.sh && echo "OK"
```
Expected: `OK`

**Step 4: Commit**

```bash
git add scripts/install-cni-metallb.sh
git commit -m "feat: add install-cni-metallb.sh for Cilium + MetalLB setup"
```

---

### Task 7: Crear scripts/delete-clusters.sh

**Files:**
- Create: `scripts/delete-clusters.sh`

**Step 1: Crear el script**

```bash
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
```

**Step 2: Dar permisos de ejecución**

```bash
chmod +x scripts/delete-clusters.sh
```

**Step 3: Verificar sintaxis bash**

```bash
bash -n scripts/delete-clusters.sh && echo "OK"
```
Expected: `OK`

**Step 4: Commit**

```bash
git add scripts/delete-clusters.sh
git commit -m "feat: add delete-clusters.sh with kubeconfig cleanup"
```

---

### Task 8: Crear scripts/status.sh

**Files:**
- Create: `scripts/status.sh`

**Step 1: Crear el script**

```bash
#!/usr/bin/env bash
set -euo pipefail

CLUSTERS=("dev-cluster" "pro-cluster")

show_cluster_status() {
  local name="$1"
  local context="kind-${name}"

  echo "════════════════════════════════════════════════════════"
  echo "  CLUSTER: $name"
  echo "════════════════════════════════════════════════════════"

  if ! kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    echo "  [NO EXISTE]"
    echo ""
    return
  fi

  echo ""
  echo "--- Nodos ---"
  kubectl --context="$context" get nodes -o wide 2>/dev/null || echo "  (error obteniendo nodos)"

  echo ""
  echo "--- Cilium (kube-system) ---"
  kubectl --context="$context" get pods -n kube-system \
    -l k8s-app=cilium \
    -o wide 2>/dev/null || echo "  (Cilium no instalado)"

  echo ""
  echo "--- MetalLB (metallb-system) ---"
  kubectl --context="$context" get pods -n metallb-system \
    -o wide 2>/dev/null || echo "  (MetalLB no instalado)"

  echo ""
  echo "--- Servicios LoadBalancer ---"
  kubectl --context="$context" get svc -A \
    --field-selector spec.type=LoadBalancer \
    -o wide 2>/dev/null || echo "  (ninguno)"

  echo ""
}

for cluster in "${CLUSTERS[@]}"; do
  show_cluster_status "$cluster"
done
```

**Step 2: Dar permisos de ejecución**

```bash
chmod +x scripts/status.sh
```

**Step 3: Verificar sintaxis bash**

```bash
bash -n scripts/status.sh && echo "OK"
```
Expected: `OK`

**Step 4: Commit**

```bash
git add scripts/status.sh
git commit -m "feat: add status.sh showing nodes, Cilium, MetalLB and LoadBalancer IPs"
```

---

### Task 9: Crear README.md

**Files:**
- Create: `README.md`

**Step 1: Crear el README**

Contenido:

```markdown
# Kind Clusters: dev / pro

Dos clusters kind locales para desarrollo y labs de seguridad (CKS).

**Stack:** Cilium (CNI + kube-proxy replacement) · MetalLB (LoadBalancer L2) · preparado para Istio multicluster

---

## Arquitectura

```
┌─────────────────────────────┐   ┌─────────────────────────────┐
│        dev-cluster          │   │        pro-cluster          │
│  API: localhost:6450        │   │  API: localhost:6451        │
│  Pods:  10.10.0.0/16       │   │  Pods:  10.30.0.0/16       │
│  Svcs:  10.20.0.0/16       │   │  Svcs:  10.40.0.0/16       │
│  MetalLB: 172.18.0.120-130 │   │  MetalLB: 172.18.0.131-140 │
│  1 control-plane + 3 workers│   │  1 control-plane + 3 workers│
└─────────────────────────────┘   └─────────────────────────────┘
```

---

## CIDRs y Puertos

### Redes

| Cluster | API Port | Pod CIDR     | Svc CIDR     | MetalLB Pool     |
|---------|----------|--------------|--------------|------------------|
| dev     | 6450     | 10.10.0.0/16 | 10.20.0.0/16 | 172.18.0.120–130 |
| pro     | 6451     | 10.30.0.0/16 | 10.40.0.0/16 | 172.18.0.131–140 |

### hostPorts (fallback NodePort, activos cuando MetalLB no es accesible)

| Worker | :80 dev | :80 pro | :443 dev | :443 pro | :2222 dev | :2222 pro |
|--------|---------|---------|----------|----------|-----------|-----------|
| w1     | 9090    | 9093    | 8440     | 8450     | 2030      | 2130      |
| w2     | 9091    | 9094    | 8441     | 8451     | 2031      | 2131      |
| w3     | 9092    | 9095    | 8442     | 8452     | 2032      | 2132      |

> El puerto 2222 está reservado para un bastion/jump pod con servidor SSH dentro del cluster.

---

## Prerequisitos

```bash
# Verificar herramientas necesarias
docker --version       # Docker Engine corriendo
kind version           # >= 0.20
kubectl version --client
helm version           # >= 3.x
# cilium CLI se instala automáticamente con install-cni-metallb.sh si no existe
```

---

## Uso

### 1. Crear los clusters

```bash
# Ambos clusters
./scripts/create-clusters.sh

# Solo uno
./scripts/create-clusters.sh dev
./scripts/create-clusters.sh pro
```

### 2. Instalar Cilium + MetalLB

Ejecutar por separado para cada cluster:

```bash
./scripts/install-cni-metallb.sh dev
./scripts/install-cni-metallb.sh pro
```

Este script:
- Instala Cilium CLI si no existe
- Instala Cilium (reemplaza kube-proxy)
- Instala MetalLB via Helm
- Aplica el pool de IPs correspondiente

### 3. Verificar estado

```bash
./scripts/status.sh
```

### 4. Eliminar clusters

```bash
# Ambos clusters
./scripts/delete-clusters.sh

# Solo uno
./scripts/delete-clusters.sh dev
./scripts/delete-clusters.sh pro
```

---

## Estructura del repositorio

```
.
├── dev/kind/
│   ├── dev-cluster.yaml        # Configuración kind del cluster dev
│   └── metallb-ippool.yaml     # Pool de IPs MetalLB para dev
├── pro/kind/
│   ├── pro-cluster.yaml        # Configuración kind del cluster pro
│   └── metallb-ippool.yaml     # Pool de IPs MetalLB para pro
├── scripts/
│   ├── create-clusters.sh      # Crea clusters (verifica Docker y puertos)
│   ├── install-cni-metallb.sh  # Instala Cilium + MetalLB
│   ├── delete-clusters.sh      # Elimina clusters y limpia kubeconfig
│   └── status.sh               # Estado de nodos, CNI, LB e IPs
├── components/
│   ├── argocd/                 # Valores Helm de ArgoCD
│   └── apisix/                 # Chart de APISIX
└── docs/plans/                 # Documentos de diseño e implementación
```

---

## Troubleshooting

### MetalLB no asigna IPs (EXTERNAL-IP en `<pending>`)

Verificar que el pool de IPs está en el rango correcto de la red Docker:

```bash
# Ver la subred del bridge kind
docker network inspect kind | grep -A5 "IPAM"

# Si la subred no es 172.18.x.x, actualizar metallb-ippool.yaml con el rango correcto
# y reaplicar:
kubectl apply -f dev/kind/metallb-ippool.yaml  # o pro/
```

### Cilium no arranca (pods en CrashLoopBackOff)

```bash
# Ver logs del pod
kubectl logs -n kube-system -l k8s-app=cilium --previous

# Verificar que el kernel tiene los módulos necesarios
lsmod | grep -E "ip_tables|xt_"
```

### kind create cluster falla por puertos en uso

```bash
# Ver qué proceso usa el puerto
ss -tlnp sport = :6450

# Ver si el cluster ya existe
kind get clusters
```

### Acceso desde host cuando MetalLB no funciona

Usar los hostPorts de fallback mapeados directamente al nodo:

```bash
curl http://localhost:9090   # worker 1 del dev-cluster, puerto 80
curl http://localhost:9093   # worker 1 del pro-cluster, puerto 80
```

---

## Notas: Istio Multicluster (futuro)

Los CIDRs están intencionalmente separados entre clusters:
- dev: pods `10.10.0.0/16`, services `10.20.0.0/16`
- pro: pods `10.30.0.0/16`, services `10.40.0.0/16`

Esta separación es un prerequisito para configurar Istio multicluster con malla de servicios entre ambos clusters. No hay implementación de Istio en este repositorio actualmente.

Para implementarlo en el futuro, consultar la documentación oficial de Istio multicluster con primary-remote o multi-primary topology.

---

## Falco (labs CKS)

Los nodos tienen los mounts necesarios para Falco:
- `/var/run/docker.sock` — Falco con Docker runtime
- `/sys/kernel/security` — Falco + AppArmor
- `/dev` — acceso a dispositivos del kernel

Falco no está instalado por defecto. Instalarlo con Helm cuando se necesite para los labs:

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco -n falco --create-namespace
```
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with architecture, ports, scripts usage and troubleshooting"
```

---

### Task 10: Commit final y verificación de estructura

**Step 1: Verificar estructura completa**

```bash
find . -not -path './.git/*' -not -path './components/apisix/apisix-helm-chart/*' -type f | sort
```

Expected output incluye:
```
./dev/kind/dev-cluster.yaml
./dev/kind/metallb-ippool.yaml
./docs/plans/2026-04-06-kind-clusters-dev-pro-design.md
./docs/plans/2026-04-06-kind-clusters-implementation.md
./pro/kind/metallb-ippool.yaml
./pro/kind/pro-cluster.yaml
./README.md
./scripts/create-clusters.sh
./scripts/delete-clusters.sh
./scripts/install-cni-metallb.sh
./scripts/status.sh
```

**Step 2: Verificar todos los scripts tienen permisos de ejecución**

```bash
ls -la scripts/
```
Expected: todos con `-rwxr-xr-x`

**Step 3: Verificar sintaxis de todos los scripts**

```bash
for f in scripts/*.sh; do bash -n "$f" && echo "OK: $f"; done
```
Expected: `OK` para cada script

**Step 4: Verificar todos los YAMLs**

```bash
for f in dev/kind/*.yaml pro/kind/*.yaml; do
  python3 -c "import yaml; list(yaml.safe_load_all(open('$f')))" && echo "OK: $f"
done
```
Expected: `OK` para cada fichero
