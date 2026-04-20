# Kind Clusters: dev / pro

Plataforma de laboratorio con dos clusters kind locales para aprender herramientas cloud-native de forma progresiva. El proyecto está en evolución continua.

**Stack actual:** Cilium · MetalLB · APISIX · ArgoCD · Vault + VSO

---

## Arquitectura

```
                        ┌── MetalLB L2 ──────────────────────────────┐
                        │  dev: 172.18.0.120–130                     │
                        │  pro: 172.18.0.131–140                     │
                        └────────────────────────────────────────────┘
                                         │
              ┌──────────────────────────┼──────────────────────────┐
              │                          │                          │
   ┌──────────▼──────────┐              │             ┌────────────▼────────┐
   │     dev-cluster     │              │             │     pro-cluster     │
   │  API: :6450         │              │             │  API: :6451         │
   │  Pods: 10.10.0.0/16 │              │             │  Pods: 10.30.0.0/16 │
   │  Svcs: 10.20.0.0/16 │◄── Istio ───►             │  Svcs: 10.40.0.0/16 │
   │                     │  East-West   │             │                     │
   │  ┌───────────────┐  │  (futuro)    │             │  ┌───────────────┐  │
   │  │ APISIX        │  │              │             │  │ APISIX        │  │
   │  │ norte-sur     │  │              │             │  │ norte-sur     │  │
   │  └───────────────┘  │              │             │  └───────────────┘  │
   │  ┌───────────────┐  │              │             │  ┌───────────────┐  │
   │  │ Istio Gateway │  │              │             │  │ Istio Gateway │  │
   │  │ (futuro)      │  │              │             │  │ (futuro)      │  │
   │  └───────────────┘  │              │             │  └───────────────┘  │
   └─────────────────────┘              │             └─────────────────────┘
```

---

## Redes y Puertos

### CIDRs

| Cluster | API Port | Pod CIDR     | Svc CIDR     | MetalLB Pool      |
| ------- | -------- | ------------ | ------------ | ----------------- |
| dev     | 6440     | 10.10.0.0/16 | 10.20.0.0/16 | 172.18.0.120–130 |
| pro     | 6445     | 10.30.0.0/16 | 10.40.0.0/16 | 172.18.0.131–140 |

Los CIDRs están intencionalmente separados — requisito para Istio multicluster.

### hostPorts (fallback NodePort cuando MetalLB no es accesible)

| Worker | :80 dev | :80 pro | :443 dev | :443 pro | :2222 dev | :2222 pro |
| ------ | ------- | ------- | -------- | -------- | --------- | --------- |
| w1     | 9090    | 9093    | 8440     | 8450     | 2030      | 2130      |
| w2     | 9091    | 9094    | 8441     | 8451     | 2031      | 2131      |
| w3     | 9092    | 9095    | 8442     | 8452     | 2032      | 2132      |

> El puerto 2222 está reservado para un bastion/jump pod con servidor SSH dentro del cluster.

---

## Componentes

### Implementado

| Componente | Namespace | Función |
|---|---|---|
| **Cilium** | `kube-system` | CNI + reemplazo de kube-proxy |
| **MetalLB** | `metallb-system` | LoadBalancer L2 para kind |
| **APISIX** | `ingress-apisix` | Ingress norte-sur, API gateway, plugins |
| **ArgoCD** | `argocd` | CD declarativo — dev: standalone, pro: HA |
| **Vault** | `vault` | Gestión centralizada de secretos — dev: standalone, pro: HA Raft |
| **Vault Secrets Operator** | `vault-secrets-operator` | Sincronización Vault → Kubernetes Secrets |

### Roadmap

#### Ingress y Service Mesh

| Componente | Función |
| --- | --- |
| **Istio** | Service mesh este-oeste + Ingress Gateway norte-sur + multicluster entre dev/pro |

#### Observabilidad

| Componente | Función |
| --- | --- |
| **Prometheus** | Métricas del cluster y aplicaciones |
| **Grafana** | Dashboards y visualización |
| **Fluent Bit** | Recolección y envío de logs |

#### GitOps avanzado

| Componente | Función |
| --- | --- |
| **Kargo** | Promoción progresiva entre entornos (dev → pro) |

#### Seguridad

| Componente | Función |
| --- | --- |
| **Kyverno** | Políticas de admisión, validación y mutación |
| **Falco** | Detección de amenazas en runtime (syscalls) |

---

## Prerequisitos

```bash
docker --version       # Docker Engine corriendo
kind version           # >= 0.20
kubectl version --client
helm version           # >= 3.x
# cilium CLI se instala automáticamente con 02-install-cni-metallb.sh si no existe
```

---

## Instalación

### 1. Crear los clusters

```bash
./scripts/01-create-clusters.sh dev
./scripts/01-create-clusters.sh pro
```

### 2. Instalar Cilium + MetalLB

```bash
./scripts/02-install-cni-metallb.sh dev
./scripts/02-install-cni-metallb.sh pro
```

### 3. Instalar APISIX

```bash
./scripts/03-install-apisix.sh dev
./scripts/03-install-apisix.sh pro
```

**Demo httpbin con rate limiting:**

```bash
kubectl apply -f components/ingress/apisix/crds/httpbin/

EXTERNAL_IP=$(kubectl get svc apisix-gateway -n ingress-apisix \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -H "Host: httpbin.local" http://${EXTERNAL_IP}/get
```

### 4. Instalar ArgoCD

```bash
./scripts/04-install-argocd.sh dev
./scripts/04-install-argocd.sh pro
```

### 5. Instalar Vault + VSO

```bash
./scripts/05-install-vault.sh dev
# Después del script: init y unseal manual
kubectl exec -n vault vault-0 -- vault operator init
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>
# Configurar Vault y sembrar secrets
./scripts/05-seed-vault.sh dev
```

### 6. Aplicar App of Apps (ArgoCD gestiona el resto)

```bash
kubectl apply -f argo-manifests/kind/argo-apps-kind.yml --context kind-dev-cluster
```

---

## Orden de operaciones

Los scripts instalan la infraestructura base. ArgoCD toma el control a partir del paso 6.

**Vault, VSO y APISIX no los gestiona ArgoCD** — son prerequisitos que deben estar listos antes de aplicar el App of Apps. Los secrets de Vault deben estar sembrados antes de que ArgoCD sincronice Keycloak (wave 4 necesita los Kubernetes Secrets creados por VSO en wave 3).

```
scripts 01→05 → init+unseal vault → seed-vault → argo-apps-kind.yml
                                                         │
                                     ArgoCD Wave 1: operators (kyverno, mongodb, crossplane)
                                     ArgoCD Wave 3: keycloak-secrets (VSO), prometheus
                                     ArgoCD Wave 4: keycloak, grafana, kargo
```

---

## Estructura del repositorio

```
.
├── env/
│   ├── dev/
│   │   ├── dev-cluster.yaml
│   │   └── metallb-ippool.yaml
│   └── pro/
│       ├── pro-cluster.yaml
│       └── metallb-ippool.yaml
│
├── scripts/
│   ├── 00-status.sh
│   ├── 01-create-clusters.sh
│   ├── 02-install-cni-metallb.sh
│   ├── 03-install-apisix.sh
│   ├── 04-install-argocd.sh
│   ├── 05-install-vault.sh
│   ├── 05-seed-vault.sh
│   └── 99-delete-clusters.sh
│
├── components/
│   ├── ingress/apisix/
│   │   ├── config/             # apisix-config.yaml (gitignored)
│   │   └── crds/httpbin/       # ApisixRoute + ApisixUpstream + Deployment
│   ├── argocd/
│   │   ├── dev/values-local.yaml
│   │   └── pro/values-ha.yaml
│   ├── vault/
│   │   ├── dev/                # values-vault.yaml, values-vso.yaml
│   │   ├── pro/                # values-vault.yaml (HA Raft), values-vso.yaml
│   │   └── setup/              # policy-keycloak.hcl, seed-secrets.sh
│   └── apps/
│       ├── curl/
│       ├── httpbin/
│       └── sleep/
│
├── docs/
│   ├── COMPONENTS.md
│   ├── LABS.md
│   ├── vault/
│   └── velero/
│
└── secrets/                    # gitignored — vault-init-dev.txt, vault-init-pro.txt
```

---

## Namespaces y aislamiento de Istio

| Namespace | Componente | Istio sidecar |
| --- | --- | --- |
| `ingress-apisix` | APISIX gateway | `disabled` |
| `demo-apis` | Apps de demo (httpbin...) | `disabled` (hasta instalar Istio) |
| `istio-system` | Control plane Istio (futuro) | — |
| `istio-ingress` | Ingress Gateway Istio (futuro) | — |

---

## Troubleshooting

### MetalLB no asigna IPs (`EXTERNAL-IP` en `<pending>`)

```bash
# Ver la subred del bridge kind
docker network inspect kind | grep -A5 "IPAM"

# Si la subred no es 172.18.x.x, actualizar metallb-ippool.yaml con el rango correcto
kubectl apply -f env/dev/metallb-ippool.yaml   # o env/pro/
```

### Cilium no arranca (CrashLoopBackOff)

```bash
kubectl logs -n kube-system -l k8s-app=cilium --previous
lsmod | grep -E "ip_tables|xt_"
```

### kind create cluster falla por puertos en uso

```bash
ss -tlnp | grep :6450
kind get clusters
```

### Acceso desde host sin MetalLB

```bash
curl http://localhost:9090   # worker 1 dev, puerto 80
curl http://localhost:9093   # worker 1 pro, puerto 80
```
