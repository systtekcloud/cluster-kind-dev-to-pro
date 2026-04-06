# Design: APISIX Ingress Controller en kind clusters dev/pro

**Fecha:** 2026-04-06  
**Estado:** Aprobado

## Contexto

Instalación de APISIX como ingress controller norte-sur en los clusters kind dev/pro existentes. Objetivo inmediato: verificar que MetalLB asigna IPs externas correctamente y disponer de un entorno para practicar plugins (rate limiting, auth, etc.). Coexistirá con Istio (instalación futura) en namespaces separados.

## Arquitectura

```
MetalLB Pool (dev: 172.18.0.120-130)
│
├── IP asignada → APISIX LoadBalancer Service (ingress-apisix)
│                  └── ApisixRoute → httpbin (demo-apis)
│
└── IP reservada → Istio Gateway (instalación futura)
```

## Namespaces

| Namespace | Contenido | Istio sidecar injection |
|-----------|-----------|------------------------|
| `ingress-apisix` | APISIX control plane + gateway | disabled (label explícito) |
| `demo-apis` | Apps de demo (httpbin, otel futuro) | disabled (por ahora) |

## Ficheros

```
scripts/
└── install-apisix.sh                          # nuevo — acepta dev|pro

components/apisix/apisix-values/
└── values-apisix.yaml                         # fix: namespace en endpoint línea 51

components/ingress/apisix/crds/httpbin/
├── httpbin-deploy.yaml                        # nuevo — Deployment + Service httpbin
├── httpbin-route.yaml                         # existente — ApisixRoute (namespace: demo-apis)
└── httpbin-upstream.yaml                      # existente — ApisixUpstream (namespace: demo-apis)
```

## Fix en values-apisix.yaml

Error en el endpoint del ingress-controller: referencia a namespace incorrecto.

```yaml
# línea 51 — actual (incorrecto):
- http://apisix-admin.apisix-ingress.svc.cluster.local:9180

# correcto:
- http://apisix-admin.ingress-apisix.svc.cluster.local:9180
```

## Script install-apisix.sh

Acepta `dev` o `pro` como argumento.

1. Valida argumento y selecciona contexto (`kind-dev-cluster` / `kind-pro-cluster`)
2. Crea namespace `ingress-apisix` con label `istio-injection: disabled`
3. `helm repo add apisix https://charts.apiseven.com && helm repo update apisix`
4. `helm upgrade --install apisix apisix/apisix -n ingress-apisix -f components/apisix/apisix-values/values-apisix.yaml`
5. Espera a que el pod de APISIX esté Running
6. Espera a que el Service LoadBalancer tenga EXTERNAL-IP asignada (MetalLB)
7. Muestra la IP externa asignada y un comando curl de prueba

## Demo httpbin (aplicación separada, manual)

No se incluye en el script de instalación de APISIX. Se aplica manualmente:

1. Crear namespace `demo-apis` con `istio-injection: disabled`
2. Aplicar `httpbin-deploy.yaml` (Deployment + Service httpbin estándar)
3. Aplicar `httpbin-upstream.yaml` (ApisixUpstream en `demo-apis`)
4. Aplicar `httpbin-route.yaml` (ApisixRoute en `demo-apis`, host: `httpbin.local`, rate limit: 5 req/60s)

Verificación: `curl -H "Host: httpbin.local" http://<EXTERNAL-IP>/get`

## Decisiones de diseño

### Helm release name: `apisix`, namespace: `ingress-apisix`
El admin service generado por Helm será `apisix-admin.ingress-apisix.svc.cluster.local:9180`, que es lo que referencia el ingress-controller embebido en el chart.

### AdminKey hardcodeado
`edd1c9f034335f136f87ad84b625c8f1` — clave por defecto para labs. Se integrará con Vault en el futuro.

### ApisixRoute CRDs (no Gateway API)
Se usan las CRDs propias de APISIX (`ApisixRoute`, `ApisixUpstream`) por simplicidad y para aprovechar los manifests ya existentes en `components/ingress/apisix/crds/`. Migración a Gateway API se considerará cuando se integre Istio.

### Demo separada del install
`install-apisix.sh` solo instala el control plane. Las apps de demo se aplican manualmente para mantener separación entre infraestructura y aplicaciones.

## Notas futuras: Istio

Cuando se instale Istio, su gateway tendrá su propia IP de MetalLB. El namespace `ingress-apisix` permanece excluido del sidecar injection mediante el label `istio-injection: disabled`. Los namespaces de apps bajo Istio (`istio-demo`, etc.) sí tendrán injection habilitado.
