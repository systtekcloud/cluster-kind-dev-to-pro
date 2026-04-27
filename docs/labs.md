# Labs

Labs progresivos para aprender las herramientas del stack cloud-native. Cada bloque construye sobre el anterior.

---

## Bloque 1 — Infraestructura base

| Lab | Nombre | Componentes | Estado |
|---|---|---|---|
| 01 | Clusters kind con Cilium y MetalLB | kind, Cilium, MetalLB | ✅ |
| 02 | API Gateway con APISIX | APISIX, ApisixRoute, httpbin | ✅ |

### Lab 01 — Clusters kind con Cilium y MetalLB

**Objetivos:**
- Crear dos clusters kind con CIDRs separados (prerequisito para multicluster Istio futuro)
- Instalar Cilium como CNI reemplazando kube-proxy
- Configurar MetalLB en modo L2 para tener LoadBalancer IPs en local

**Punto de entrada:**
```bash
./scripts/01-create-clusters.sh dev
./scripts/02-install-cni-metallb.sh dev
./scripts/00-status.sh
```

### Lab 02 — API Gateway con APISIX

**Objetivos:**
- Entender la diferencia entre ApisixRoute y ApisixUpstream
- Exponer un servicio (httpbin) a través del gateway con una ruta HTTP
- Configurar rate limiting con el plugin `limit-count`
- Verificar el comportamiento con curl

**Punto de entrada:**
```bash
./scripts/03-install-apisix.sh dev
kubectl apply -f components/ingress/apisix/crds/httpbin/
```

---

## Bloque 2 — GitOps

| Lab | Nombre | Componentes | Estado |
|---|---|---|---|
| 03 | App of Apps con ArgoCD | ArgoCD, AppProject, sync waves | 🔧 |
| 04 | Promoción dev → pro con Kargo | Kargo, ArgoCD | 📅 |

### Lab 03 — App of Apps con ArgoCD

**Objetivos:**
- Entender el patrón App of Apps: una Application raíz que gestiona otras Applications
- Configurar un AppProject con permisos y repositorios autorizados
- Usar sync waves para ordenar el despliegue de dependencias
- Usar multi-source para fusionar base/ y overlays/kind/ en una sola Application

**Punto de entrada:**
```bash
./scripts/04-install-argocd.sh dev
kubectl apply -f argo-manifests/kind/argo-apps-kind.yml --context kind-dev-cluster
```

**Repo GitOps:** `https://gitlab.com/eks-vcluster-platform/gitops-base-platform.git`
Manifiesto de entrada: `argo-manifests/kind/argo-apps-kind.yml`

### Lab 04 — Promoción dev → pro con Kargo

**Componentes:** Kargo, ArgoCD

---

## Bloque 3 — Secretos y seguridad

| Lab | Nombre | Componentes | Estado |
|---|---|---|---|
| 05 | Vault: instalación, init, unseal, KV engine | Vault | ✅ |
| 06 | VSO: sincronizar secrets Vault → Kubernetes | VSO, VaultStaticSecret, VaultAuth | 🔧 |
| 07 | Keycloak con secrets gestionados por Vault | Keycloak, VSO, PostgreSQL | 🔧 |
| 08 | Políticas de admisión con Kyverno | Kyverno | 📅 |
| 09 | Runtime security con Falco | Falco | 📅 |

### Lab 05 — Vault: instalación, init, unseal, KV engine

**Objetivos:**
- Entender la diferencia entre `vault operator init` y `vault operator unseal`
- Desplegar Vault standalone (dev) y HA Raft 3 nodos (pro)
- Realizar el init manual y guardar el material de bootstrap de forma segura
- Habilitar el KV v2 engine y configurar el Kubernetes auth method
- Crear una policy de lectura y vincularla a un role

**Punto de entrada:**
```bash
./scripts/05-install-vault.sh dev
kubectl exec -n vault vault-0 -- vault operator init
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>
./scripts/05-seed-vault.sh dev
```

**Documentación:** `docs/vault/vault-setup.md`

### Lab 06 — VSO: sincronizar secrets Vault → Kubernetes

**Objetivos:**
- Entender por qué VSO existe: operadores de terceros no hablan con Vault
- Crear un VaultAuth que vincule un ServiceAccount de Kubernetes con un role de Vault
- Crear un VaultStaticSecret que sincronice un path de Vault como Kubernetes Secret
- Verificar que el Secret se crea y se actualiza al cambiar el valor en Vault

**Punto de entrada:**
```bash
kubectl apply -f gitops/platform/jobs/keycloak-secrets/keycloak-secrets.yaml
```
(repo: `https://gitlab.com/eks-vcluster-platform/gitops-base-platform.git`)

**Documentación:** `docs/vault/vault-resources.md`

### Lab 07 — Keycloak con secrets gestionados por Vault

**Objetivos:**
- Desplegar Keycloak + PostgreSQL via ArgoCD con el patrón App of Apps
- Los passwords de Keycloak los gestiona Vault (no están en git)
- VSO crea los Kubernetes Secrets antes de que Keycloak arranque (sync waves)
- Verificar el flujo completo: Vault → VSO → K8s Secret → Keycloak

**Punto de entrada:** Requiere Labs 03, 05 y 06 completados.

### Lab 08 — Políticas de admisión con Kyverno

**Componentes:** Kyverno

### Lab 09 — Runtime security con Falco

**Componentes:** Falco

---

## Bloque 4 — Observabilidad

| Lab | Nombre | Componentes | Estado |
|---|---|---|---|
| 10 | Métricas con Prometheus y Grafana | Prometheus, Grafana | 📅 |
| 11 | Logs con Fluent Bit | Fluent Bit | 📅 |

---

## Bloque 5 — Service Mesh

| Lab | Nombre | Componentes | Estado |
|---|---|---|---|
| 12 | Istio: instalación y sidecar injection | Istio | 📅 |
| 13 | Istio multicluster dev ↔ pro | Istio, MetalLB | 📅 |

---

## Leyenda

| Icono | Significado |
|---|---|
| ✅ | Lab disponible |
| 🔧 | En progreso |
| 📅 | Pendiente |
