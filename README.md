# Kind Clusters: dev / pro

Plataforma de laboratorio con dos clusters kind locales para desarrollo, labs de seguridad (CKS/CKAD) e integración de herramientas cloud-native. El proyecto está en evolución continua.

**Stack actual:** Cilium · MetalLB · APISIX

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

| Componente        | Namespace          | Función                                |
| ----------------- | ------------------ | --------------------------------------- |
| **Cilium**  | `kube-system`    | CNI + reemplazo de kube-proxy           |
| **MetalLB** | `metallb-system` | LoadBalancer L2 para kind               |
| **APISIX**  | `ingress-apisix` | Ingress norte-sur, API gateway, plugins |

### Roadmap

#### Ingress y Service Mesh

| Componente      | Función                                                                         |
| --------------- | -------------------------------------------------------------------------------- |
| **Istio** | Service mesh este-oeste + Ingress Gateway norte-sur + multicluster entre dev/pro |

#### Observabilidad

| Componente              | Función                             |
| ----------------------- | ------------------------------------ |
| **Prometheus**    | Métricas del cluster y aplicaciones |
| **Grafana**       | Dashboards y visualización          |
| **Elasticsearch** | Almacenamiento y búsqueda de logs   |
| **Fluent Bit**    | Recolección y envío de logs        |

#### Escalado

| Componente     | Función                                                  |
| -------------- | --------------------------------------------------------- |
| **KEDA** | Autoscaling basado en eventos (colas, métricas externas) |

#### GitOps

| Componente       | Función                                          |
| ---------------- | ------------------------------------------------- |
| **ArgoCD** | CD declarativo, sincronización con git           |
| **Kargo**  | Promoción progresiva entre entornos (dev → pro) |

#### Seguridad

| Componente                       | Función                                         |
| -------------------------------- | ------------------------------------------------ |
| **Falco**                  | Detección de amenazas en runtime (syscalls)     |
| **Kyverno**                | Políticas de admisión, validación y mutación |
| **Vault**                  | Gestión centralizada de secretos                |
| **Vault Secrets Operator** | Sincronización de secretos Vault → Kubernetes  |

---

## Prerequisitos

```bash
docker --version       # Docker Engine corriendo
kind version           # >= 0.20
kubectl version --client
helm version           # >= 3.x
# cilium CLI se instala automáticamente con install-cni-metallb.sh si no existe
```

---

## Instalación

### 1. Crear los clusters

```bash
./scripts/create-clusters.sh        # ambos
./scripts/create-clusters.sh dev    # solo dev
./scripts/create-clusters.sh pro    # solo pro
```

### 2. Instalar Cilium + MetalLB

```bash
./scripts/install-cni-metallb.sh dev
./scripts/install-cni-metallb.sh pro
```

Instala Cilium CLI si no existe, Cilium (reemplaza kube-proxy), MetalLB via Helm y aplica el pool de IPs del cluster.

### 3. Instalar APISIX

```bash
./scripts/install-apisix.sh dev
./scripts/install-apisix.sh pro
```

Crea el namespace `ingress-apisix` (con `istio-injection: disabled`), instala APISIX via Helm y espera a que MetalLB asigne la IP externa.

**Demo httpbin con rate limiting:**

```bash
kubectl apply -f components/ingress/apisix/crds/httpbin/

EXTERNAL_IP=$(kubectl get svc apisix-gateway -n ingress-apisix \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -H "Host: httpbin.local" http://${EXTERNAL_IP}/get
```

### 4. Estado y limpieza

```bash
./scripts/status.sh             # nodos, Cilium, MetalLB, LoadBalancers
./scripts/delete-clusters.sh    # ambos clusters
./scripts/delete-clusters.sh dev
```

---

## Estructura del repositorio

```
.
├── dev/kind/
│   ├── dev-cluster.yaml            # Configuración kind del cluster dev
│   └── metallb-ippool.yaml         # Pool de IPs MetalLB dev (172.18.0.120–130)
├── pro/kind/
│   ├── pro-cluster.yaml            # Configuración kind del cluster pro
│   └── metallb-ippool.yaml         # Pool de IPs MetalLB pro (172.18.0.131–140)
├── scripts/
│   ├── create-clusters.sh          # Crea clusters (verifica Docker y puertos)
│   ├── install-cni-metallb.sh      # Instala Cilium + MetalLB
│   ├── install-apisix.sh           # Instala APISIX ingress controller
│   ├── delete-clusters.sh          # Elimina clusters y limpia kubeconfig
│   └── status.sh                   # Estado de nodos, CNI, LB e IPs
├── components/
│   ├── apisix/
│   │   └── apisix-values/          # Valores Helm para APISIX
│   ├── ingress/
│   │   └── apisix/crds/            # ApisixRoute, ApisixUpstream (httpbin demo)
│   └── argocd/                     # (pendiente) Valores Helm para ArgoCD
└── docs/plans/                     # Documentos de diseño e implementación
```

---

## Namespaces y aislamiento de Istio

| Namespace          | Componente                      | Istio sidecar                       |
| ------------------ | ------------------------------- | ----------------------------------- |
| `ingress-apisix` | APISIX gateway                  | `disabled`                        |
| `demo-apis`      | Apps de demo (httpbin, otel...) | `disabled` (hasta instalar Istio) |
| `istio-system`   | Control plane Istio (futuro)    | —                                  |
| `istio-ingress`  | Ingress Gateway Istio (futuro)  | —                                  |

---

## Troubleshooting

### MetalLB no asigna IPs (`EXTERNAL-IP` en `<pending>`)

```bash
# Ver la subred del bridge kind
docker network inspect kind | grep -A5 "IPAM"

# Si la subred no es 172.18.x.x, actualizar metallb-ippool.yaml con el rango correcto
kubectl apply -f dev/kind/metallb-ippool.yaml   # o pro/
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

---

## Falco (labs CKS)

Los nodos tienen montados los recursos necesarios para Falco:

- `/var/run/docker.sock` — runtime Docker
- `/sys/kernel/security` — AppArmor
- `/dev` — acceso a dispositivos del kernel

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco -n falco --create-namespace
```
