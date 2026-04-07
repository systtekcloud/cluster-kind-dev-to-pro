# Labs Disponibles

Labs para práctica de CKAD, CKS y tecnologías cloud-native.

## CKAD - Kubernetes Application Developer

| Lab | Tema | Componentes | Estado |
|-----|------|-------------|--------|
| 01 | Pods, ConfigMaps, Secrets | Helm | 📅 Pendiente |
| 02 | Deployments, Services | ArgoCD | 📅 Pendiente |
| 03 | Jobs, CronJobs | Argo Workflows | 📅 Pendiente |
| 04 | Probes, Resources | KEDA | 📅 Pendiente |
| 05 | Ingress, NetworkPolicies | APISIX, Cilium | 📅 Pendiente |
| 06 | Multi-container pods | - | 📅 Pendiente |
| 07 | PV, PVC, StorageClass | - | 📅 Pendiente |

## CKS - Kubernetes Security Specialist

| Lab | Tema | Componentes | Estado |
|-----|------|-------------|--------|
| 01 | Runtime Security | Falco | 📚 Documentado |
| 02 | Network Policies | Cilium | 📅 Pendiente |
| 03 | Pod Security Standards | - | 📅 Pendiente |
| 04 | RBAC | - | 📅 Pendiente |
| 05 | Secrets Management | Vault | 📅 Pendiente |
| 06 | Image Security | Trivy | 📅 Pendiente |
| 07 | Audit Logging | - | 📅 Pendiente |

## GitOps

| Lab | Tema | Componentes | Estado |
|-----|------|-------------|--------|
| 01 | App of Apps | ArgoCD | 📅 Pendiente |
| 02 | Promoción dev → pro | Kargo | 📅 Pendiente |
| 03 | Helm + ArgoCD | ArgoCD | 📅 Pendiente |

## Autenticación

| Lab | Tema | Componentes | Estado |
|-----|------|-------------|--------|
| 01 | OIDC con Keycloak | Keycloak, Prometheus | 📚 Disponible |

---

## Estructura de labs

Cada lab en `labs/{categoria}/{numero}-{nombre}/`:
- `README.md` - Instrucciones y objetivos
- Manifests necesarios
- `solution/` - Solución de referencia

## Leyenda

| Icono | Significado |
|-------|-------------|
| 📚 | Lab disponible |
| 📅 | Pendiente de crear |
