# Componentes del Cluster

Estado de componentes instalables en los clusters kind dev y pro.

## Base Stack

| Componente | Namespace | Script | Estado |
|---|---|---|---|
| Cilium | kube-system | `02-install-cni-metallb.sh` | ✅ Implementado |
| MetalLB | metallb-system | `02-install-cni-metallb.sh` | ✅ Implementado |

## Ingress / API Gateway

| Componente | Namespace | Script | Estado |
|---|---|---|---|
| APISIX | ingress-apisix | `03-install-apisix.sh` | ✅ Implementado |
| Istio Gateway | istio-ingress | — | 📅 Roadmap |

## GitOps

| Componente | Namespace | Script / fuente | Estado |
|---|---|---|---|
| ArgoCD | argocd | `04-install-argocd.sh` | ✅ Implementado |
| Kargo | kargo | via ArgoCD | 📅 Roadmap |

## Secretos

| Componente | Namespace | Script / fuente | Estado |
|---|---|---|---|
| Vault | vault | `05-install-vault.sh` | ✅ Implementado |
| Vault Secrets Operator | vault-secrets-operator | `05-install-vault.sh` | ✅ Implementado |

## Seguridad

| Componente | Namespace | Script / fuente | Estado |
|---|---|---|---|
| Kyverno | kyverno | via ArgoCD | 📅 Roadmap |
| Falco | falco | — | 📅 Roadmap |

## Autenticación

| Componente | Namespace | Script / fuente | Estado |
|---|---|---|---|
| Keycloak | keycloak | via ArgoCD | 🔧 En progreso |

## Observabilidad

| Componente | Namespace | Script / fuente | Estado |
|---|---|---|---|
| Prometheus | monitoring | via ArgoCD | 📅 Roadmap |
| Grafana | monitoring | via ArgoCD | 📅 Roadmap |
| Fluent Bit | logging | — | 📅 Roadmap |

## Apps de demo

| App | Ubicación | Propósito |
|---|---|---|
| httpbin | `components/apps/httpbin/` | Testing HTTP, rate limiting, latencia |
| curl | `components/apps/curl/` | Conectividad interna |
| sleep | `components/apps/sleep/` | Testing service mesh |

---

## Orden de instalación

```
1. ./scripts/01-create-clusters.sh dev|pro
2. ./scripts/02-install-cni-metallb.sh dev|pro
3. ./scripts/03-install-apisix.sh dev|pro          ← no gestionado por ArgoCD
4. ./scripts/04-install-argocd.sh dev|pro
5. ./scripts/05-install-vault.sh dev|pro            ← no gestionado por ArgoCD
   → init + unseal manual
   → ./scripts/05-seed-vault.sh dev|pro
6. kubectl apply -f argo-manifests/kind/argo-apps-kind.yml
   → ArgoCD sincroniza el resto (operators → keycloak-secrets → keycloak + grafana + kargo)
```

---

## Leyenda

| Icono | Significado |
|---|---|
| ✅ | Implementado |
| 🔧 | En progreso |
| 📅 | Roadmap |
