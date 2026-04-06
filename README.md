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
ss -tlnp | grep :6450

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
