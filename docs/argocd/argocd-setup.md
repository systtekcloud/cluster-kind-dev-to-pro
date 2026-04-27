# ArgoCD

## Resumen

En este repositorio ArgoCD se instala fuera del alcance de sí mismo, mediante script Helm:

- `./scripts/04-install-argocd.sh dev`
- `./scripts/04-install-argocd.sh pro`

Topología actual:

- `dev`: standalone, 1 réplica por componente
- `pro`: HA, 2 réplicas de server y repo-server, redis-ha activado
- Namespace: `argo`

Ficheros de valores:

- `components/argocd/dev/values-local.yaml`
- `components/argocd/pro/values-ha.yaml`

## Instalación

```bash
./scripts/04-install-argocd.sh dev
./scripts/04-install-argocd.sh pro
```

El script:

- añade el repositorio Helm `argo`
- hace `helm upgrade --install argo/argo-cd`
- recupera la IP del gateway APISIX
- imprime la contraseña inicial de admin

## Acceso

ArgoCD se expone a través de APISIX en modo insecure (`server.insecure: true`):

```
https://argocd-dev.local.lp
```

Credenciales iniciales:

```bash
kubectl -n argo get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

CLI local:

```bash
argocd login argocd-dev.local.lp --username admin --insecure
```

## Configuración relevante

### Dev

```yaml
configs:
  params:
    server.insecure: true   # sin TLS, APISIX termina TLS
  cm:
    timeout.reconciliation: 5s
```

### Pro

```yaml
redis-ha:
  enabled: true
server:
  replicas: 2
repoServer:
  replicas: 2
```

## Plugins instalados

### ArgoCD Vault Plugin (AVP)

Instalado como sidecar CMP en el repo-server. Permite sustituir placeholders del tipo `<path:secret/data/dev/myapp#key>` en manifiestos antes de aplicarlos al cluster.

Detalles de configuración y uso: `docs/argocd/argocd-vault-plugin.md`

## Operativa habitual

```bash
# Ver todas las Applications
kubectl get applications -n argo

# Forzar sync de una Application
argocd app sync <nombre>

# Ver logs del repo-server (donde corre AVP)
kubectl logs -n argo -l app.kubernetes.io/component=repo-server -c avp

# Ver logs del application controller
kubectl logs -n argo -l app.kubernetes.io/component=application-controller
```
