# ArgoCD Vault Plugin (AVP)

## Qué es

AVP es un Config Management Plugin (CMP) que se ejecuta como sidecar en el repo-server de ArgoCD. Intercepta el pipeline de renderizado de manifiestos y sustituye placeholders del tipo `<path:secret/data/dev/myapp#key>` con los valores reales de Vault antes de que ArgoCD aplique los manifiestos al cluster.

```
Git (YAML con placeholders)
  → ArgoCD sync
  → sidecar AVP consulta Vault
  → manifiesto final con valores reales
  → kubectl apply
```

La app no sabe que Vault existe. No necesita SDK ni variables de entorno con credenciales de Vault.

## Instalación en este proyecto

AVP está instalado como sidecar CMP en el repo-server via los values de ArgoCD:

- `components/argocd/dev/values-local.yaml`
- `components/argocd/pro/values-ha.yaml`

### Estructura en Helm values

Hay tres piezas que deben encajar:

**1. `configs.cmp.plugins` — define el plugin**

El Helm chart de ArgoCD espera el nombre del plugin como clave y solo el `spec` como valor (no el CRD completo). El chart construye el CRD alrededor del spec y genera un ConfigMap `argocd-cmp-cm` con clave `<nombre>.yaml`:

```yaml
configs:
  cmp:
    create: true
    plugins:
      argocd-vault-plugin:       # → clave en ConfigMap: argocd-vault-plugin.yaml
        allowConcurrency: true
        discover:
          find:
            command: [find, ".", -name, "*.yaml"]
        generate:
          command: [argocd-vault-plugin, generate, "."]
        lockRepo: false
```

**2. `repoServer.initContainers` — descarga el binario**

```yaml
repoServer:
  initContainers:
    - name: download-avp
      image: alpine:3.20
      command: [sh, -c]
      args:
        - wget -O /custom-tools/argocd-vault-plugin
            https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.18.1/argocd-vault-plugin_1.18.1_linux_amd64
            && chmod +x /custom-tools/argocd-vault-plugin
      volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
```

> El nombre del binario en GitHub incluye la versión: `argocd-vault-plugin_1.18.1_linux_amd64`, no `argocd-vault-plugin_linux_amd64`.

**3. `repoServer.extraContainers` — el sidecar CMP**

El `subPath` debe coincidir exactamente con la clave generada por el Helm chart (`<nombre>.yaml`):

```yaml
  extraContainers:
    - name: avp
      command: [/var/run/argocd/argocd-cmp-server]
      image: quay.io/argoproj/argocd:v3.3.8   # debe coincidir con la versión instalada
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
      env:
        - name: VAULT_ADDR
          value: http://vault.vault.svc.cluster.local:8200
        - name: AVP_TYPE
          value: vault
        - name: AVP_AUTH_TYPE
          value: k8s
        - name: AVP_K8S_ROLE
          value: argocd
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: tmp
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: argocd-vault-plugin.yaml   # coincide con la clave del ConfigMap
          name: cmp-plugin
        - mountPath: /usr/local/bin/argocd-vault-plugin
          name: custom-tools
          subPath: argocd-vault-plugin

  volumes:
    - name: custom-tools
      emptyDir: {}
    - name: cmp-plugin
      configMap:
        name: argocd-cmp-cm
```

Verificar que el sidecar está activo:

```bash
kubectl get pod -n argo -l app.kubernetes.io/component=repo-server
# Debe mostrar 2/2 READY

kubectl logs -n argo -l app.kubernetes.io/component=repo-server -c avp
```

## Cómo se autentica AVP con Vault

AVP usa el Kubernetes auth method de Vault. El sidecar corre con el ServiceAccount `argocd-repo-server` y usa su token para autenticarse:

```
sidecar AVP
  → token SA argocd-repo-server (montado automáticamente por K8s)
  → Vault kubernetes auth
  → Vault valida contra la API de K8s
  → token temporal de Vault (TTL: 24h)
  → lectura de secrets
```

Variables de entorno configuradas en el sidecar:

```yaml
env:
  - name: VAULT_ADDR
    value: http://vault.vault.svc.cluster.local:8200
  - name: AVP_TYPE
    value: vault
  - name: AVP_AUTH_TYPE
    value: k8s
  - name: AVP_K8S_ROLE
    value: argocd
```

## Crear el role de Vault para ArgoCD

Antes de usar AVP hay que crear el role en Vault que autoriza al repo-server a leer secrets:

```bash
# Port-forward o exec en vault-0
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<root-token>

# Crear policy (ajustar paths según lo que necesite leer AVP)
vault policy write argocd - <<EOF
path "secret/data/dev/*" {
  capabilities = ["read"]
}
path "secret/data/pro/*" {
  capabilities = ["read"]
}
EOF

# Crear role
vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=argo \
  policies=argocd \
  ttl=24h
```

## Sintaxis de placeholders

### Path directo

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secret
stringData:
  db-password: <path:secret/data/dev/myapp#db_password>
  api-key: <path:secret/data/dev/myapp#api_key>
```

### Formato del placeholder

```
<path:secret/data/<env>/<app>#<key>>
         ├─────┘  ├───┘  ├────┘  ├───┘
         mount    KV v2  app     clave en Vault
```

El `data/` en el medio es obligatorio para KV v2.

## Usar AVP en una Application

Una Application indica a ArgoCD que use el plugin:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argo
spec:
  source:
    repoURL: https://gitlab.com/eks-vcluster-platform/gitops-base-platform.git
    path: platform/base/myapp
    targetRevision: HEAD
    plugin:
      name: argocd-vault-plugin
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  project: platform
```

## AVP vs VSO — cuándo usar cada uno

| Caso | Usar |
|---|---|
| App que necesita secrets como K8s Secrets pre-existentes (Keycloak, operadores) | VSO |
| Helm chart con valores que contienen secrets | AVP |
| Secrets que cambian frecuentemente (rotación) | VSO (sync continuo) |
| Secrets inyectados en el manifiesto en tiempo de sync | AVP |
| Sin querer gestionar CRDs `VaultStaticSecret` por servicio | AVP |

## Vault Agent Injector

Alternativa a AVP para pods en runtime. En lugar de sustituir en el manifiesto, inyecta un sidecar en cada pod que escribe los secrets en un volumen compartido.

Ver: `docs/vault/vault-setup.md` — sección VSO en este proyecto.

Activación actual (ya habilitada en este proyecto):

```yaml
# components/vault/dev/values-vault.yaml
injector:
  enabled: true
```

El injector se activa por pod con anotaciones:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-inject-secret-config: "secret/data/dev/myapp"
  vault.hashicorp.com/role: "myapp"
```

El secret aparece en `/vault/secrets/config` dentro del pod. La app lo lee como fichero. Sin SDK, sin variables de entorno con credenciales.
