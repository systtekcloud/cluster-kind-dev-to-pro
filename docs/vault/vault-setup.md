# Vault

## Resumen

En este repositorio Vault se instala fuera de ArgoCD, mediante scripts Helm:

- `./scripts/05-install-vault.sh dev`
- `./scripts/05-install-vault.sh pro`

El `init` y el `unseal` son manuales. El instalador deja Vault y Vault Secrets Operator desplegados, pero no genera ni guarda claves por sí mismo.

Topología actual:

- `dev`: standalone, 1 pod (`vault-0`)
- `pro`: HA con Raft, 3 pods (`vault-0`, `vault-1`, `vault-2`)
- Namespace Vault: `vault`
- Namespace VSO: `vault-secrets-operator`

Ficheros de valores:

- `components/vault/dev/values-vault.yaml`
- `components/vault/dev/values-vso.yaml`
- `components/vault/pro/values-vault.yaml`
- `components/vault/pro/values-vso.yaml`

## Instalación

### Desarrollo

```bash
./scripts/05-install-vault.sh dev
```

### Producción

```bash
./scripts/05-install-vault.sh pro
```

El script:

- instala Vault vía `hashicorp/vault`
- instala Vault Secrets Operator vía `hashicorp/vault-secrets-operator`
- espera los CRDs de VSO

El siguiente paso siempre es manual: inicializar Vault y desellar los pods.

## Init y unseal manual

### Desarrollo

Para el lab `dev` basta con una sola unseal key:

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1
```

Guarda la salida en un fichero gitignored, por ejemplo:

- `secrets/vault-init-dev.txt`

Desella el pod:

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key>
```

Verifica el estado:

```bash
kubectl exec -n vault vault-0 -- vault status
```

### Producción

Para `pro` en este lab se recomienda:

- `-key-shares=5`
- `-key-threshold=3`

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3
```

Guarda la salida en un fichero gitignored, por ejemplo:

- `secrets/vault-init-pro.txt`

Desella el primer nodo:

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-3>
```

Une los peers al clúster Raft y deséllalos:

```bash
kubectl exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault vault-1 -- vault operator unseal <unseal-key>

kubectl exec -n vault vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault vault-2 -- vault operator unseal <unseal-key>
```

Comprueba el estado:

```bash
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-1 -- vault status
kubectl exec -n vault vault-2 -- vault status
```

## Configuración de Vault y siembra de secretos

Una vez Vault está inicializado y desellado:

```bash
./scripts/05-seed-vault.sh dev
./scripts/05-seed-vault.sh pro
```

También se puede pasar el root token por variable de entorno:

```bash
VAULT_ROOT_TOKEN=hvs.xxx ./scripts/05-seed-vault.sh dev
```

`05-seed-vault.sh` delega en `components/vault/setup/seed-secrets.sh` y hace de forma idempotente:

- habilitar el motor KV v2 en `secret/`
- habilitar y configurar `auth/kubernetes`
- aplicar la policy `keycloak`
- crear el role `keycloak`
- sembrar secretos de Keycloak
- sembrar secretos de MongoDB

No hace falta configurar a mano KV, Kubernetes auth, policy ni role después del `init`; el seed script ya se encarga.

## Paths de secretos en Vault

### Keycloak

- `secret/dev/keycloak`
- `secret/pro/keycloak`

Claves:

- `db_password`
- `admin_password`

El script también escribe `admin-password` para compatibilidad con consumidores que esperan esa clave al transformar el secreto.

### MongoDB

- `secret/dev/mongodb/users/admin`
- `secret/pro/mongodb/users/admin`
- `secret/dev/mongodb/users/<app-user>`
- `secret/pro/mongodb/users/<app-user>`

### Velero

Pendiente de implementar:

- `secret/dev/velero/aws`
- `secret/pro/velero/aws`

## VSO en este proyecto

VSO se despliega con:

- `components/vault/dev/values-vso.yaml`
- `components/vault/pro/values-vso.yaml`

La conexión por defecto apunta al servicio interno de Vault:

```text
http://vault.vault.svc.cluster.local:8200
```

Los recursos `VaultAuth` y `VaultStaticSecret` no se generan desde una umbrella chart. En este proyecto se definen directamente como YAMLs en el repo GitOps, por ejemplo:

- `gitops/platform/jobs/keycloak-secrets/keycloak-secrets.yaml`

## Operativa local

Para operar con el CLI local de Vault:

```bash
kubectl port-forward -n vault svc/vault 8200:8200
export VAULT_ADDR=http://127.0.0.1:8200
```

Ejemplos:

```bash
vault status
vault secrets list
vault kv get secret/dev/keycloak
```

## Auto-unseal con AWS KMS

Referencia futura para producción real en EKS. No forma parte del flujo actual en kind.

Si el despliegue evoluciona a EKS:

- mantener `dev` con init/unseal manual para lab
- mover `pro` a auto-unseal con AWS KMS

La guía específica está en:

- `docs/operations/vault-autounseal.md`
