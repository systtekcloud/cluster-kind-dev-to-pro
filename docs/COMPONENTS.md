# Componentes del Cluster

Estado de componentes instalables en los clusters kind.

## Base Stack (requerido)

| Componente | Namespace | Script | Estado |
|------------|-----------|--------|--------|
| Cilium | kube-system | install-cni-metallb.sh | ✅ Implementado |
| MetalLB | metallb-system | install-cni-metallb.sh | ✅ Implementado |

## Ingress / API Gateway

| Componente | Namespace | Script | Estado |
|------------|-----------|--------|--------|
| APISIX | ingress-apisix | install-apisix.sh | ✅ Implementado |
| Nginx Ingress | ingress-nginx | manual | 📚 Referencia |
| Istio Gateway | istio-ingress | - | 📅 Roadmap |

## GitOps

| Componente | Namespace | Script | Estado |
|------------|-----------|--------|--------|
| ArgoCD | argocd | install-argocd.sh | ✅ Implementado |
| Kargo | kargo | - | 📅 Roadmap |

## Observabilidad

| Componente | Namespace | Estado |
|------------|-----------|--------|
| Prometheus | monitoring | 📅 Roadmap |
| Grafana | monitoring | 📅 Roadmap |
| Fluent Bit | logging | 📅 Roadmap |

## Seguridad

| Componente | Namespace | Estado |
|------------|-----------|--------|
| Falco | falco | 📚 Documentado |
| Kyverno | kyverno | 📅 Roadmap |
| Vault | vault | 📅 Roadmap |

## Autenticación

| Componente | Namespace | Estado |
|------------|-----------|--------|
| Keycloak | keycloak | 📚 Lab disponible |

## Apps de Demo

| App | Ubicación | Propósito |
|-----|-----------|-----------|
| httpbin | components/apps/httpbin/ | Testing HTTP, latencia |
| curl | components/apps/curl/ | Conectividad interna |
| sleep | components/apps/sleep/ | Testing service mesh |

---

## Leyenda

| Icono | Significado |
|-------|-------------|
| ✅ | Implementado con script |
| 📚 | Documentado / Lab disponible |
| 📅 | En roadmap |
