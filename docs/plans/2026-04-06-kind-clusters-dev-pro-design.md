# Design: Kind Clusters dev/pro con Cilium + MetalLB

**Fecha:** 2026-04-06  
**Estado:** Aprobado

## Contexto

Dos clusters kind locales (dev y pro) para laboratorios de desarrollo y CKS (Certified Kubernetes Security). Stack: Cilium (CNI) + MetalLB (LoadBalancer). Preparado para Istio multicluster en el futuro.

## Estructura de ficheros

```
cluster-kind-dev-to-prod/
├── dev/kind/
│   ├── dev-cluster.yaml        # revisado + comentado
│   └── metallb-ippool.yaml     # pool: dev-pool / dev-l2-advertisement
├── pro/kind/
│   ├── pro-cluster.yaml        # renombrado desde prod-cluster.yaml
│   └── metallb-ippool.yaml     # pool: pro-pool / pro-l2-advertisement
├── scripts/
│   ├── create-clusters.sh
│   ├── install-cni-metallb.sh
│   ├── delete-clusters.sh
│   └── status.sh
└── README.md
```

## Configuración de red

| Cluster | API Port | Pod CIDR     | Svc CIDR     | MetalLB Pool     |
|---------|----------|--------------|--------------|------------------|
| dev     | 6450     | 10.10.0.0/16 | 10.20.0.0/16 | 172.18.0.120–130 |
| pro     | 6451     | 10.30.0.0/16 | 10.40.0.0/16 | 172.18.0.131–140 |

## Mapeo de puertos (hostPorts)

| Worker | :80 dev | :80 pro | :443 dev | :443 pro | :2222 dev | :2222 pro |
|--------|---------|---------|----------|----------|-----------|-----------|
| w1     | 9090    | 9093    | 8440     | 8450     | 2030      | 2130      |
| w2     | 9091    | 9094    | 8441     | 8451     | 2031      | 2131      |
| w3     | 9092    | 9095    | 8442     | 8452     | 2032      | 2132      |
| cp     | —       | —       | —        | —        | —         | —         |

> Puerto 9195 en prod-cluster.yaml original es un typo; se corrige a 9095.

## Decisiones de diseño

### extraPortMappings 80/443
Se mantienen en ambos clusters como fallback de acceso cuando las IPs de MetalLB no son accesibles (diferente red, VPN). En uso normal con MetalLB activo, el tráfico va por las IPs del pool (172.18.x.x). Documentados con comentarios en el YAML.

### Puerto 2222
Reservado para exponer un bastion/jump pod con servidor SSH dentro del cluster. No implica SSH a los nodos kind directamente.

### Mounts de seguridad
- `/var/run/docker.sock` → requerido por Falco con Docker runtime (labs CKS)
- `/sys/kernel/security` → requerido por Falco para AppArmor (labs CKS)
- `/dev` → requerido por Falco para acceso a dispositivos del kernel

### Naming convention
- Cluster dev: `dev-cluster`, contexto `kind-dev-cluster`
- Cluster pro: `pro-cluster`, contexto `kind-pro-cluster`
- MetalLB pools: `dev-pool`/`dev-l2-advertisement` y `pro-pool`/`pro-l2-advertisement`

## Scripts

### create-clusters.sh [dev|pro|all]
1. Verifica Docker activo
2. Verifica hostPorts clave no en uso (6450, 6451, 9090-9095, 8440-8452)
3. `kind create cluster --config <yaml>`

### install-cni-metallb.sh <dev|pro>
1. Selecciona contexto kubectl (`kind-dev-cluster` / `kind-pro-cluster`)
2. Instala Cilium CLI si no existe (`/usr/local/bin/cilium`)
3. `cilium install` con opciones para kind
4. Espera `cilium status --wait`
5. Instala MetalLB via Helm (`metallb/metallb`)
6. Espera a que los CRDs de MetalLB estén disponibles
7. Aplica `metallb-ippool.yaml` correspondiente
8. Verifica nodos Ready

### delete-clusters.sh [dev|pro|all]
1. `kind delete cluster --name <dev-cluster|pro-cluster>`
2. Limpia contexto del kubeconfig

### status.sh
1. Para cada cluster: estado de nodos
2. Pods de Cilium (`kube-system`, label `k8s-app=cilium`)
3. Pods de MetalLB (`metallb-system`)
4. Servicios LoadBalancer con EXTERNAL-IP asignada

## Notas futuras: Istio multicluster
Los CIDRs de pods y servicios están intencionalmente separados (dev: 10.10-20.x, pro: 10.30-40.x) para facilitar la configuración de Istio multicluster cuando se implemente. No se documenta la implementación aquí.
