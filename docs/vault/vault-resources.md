# Recursos VSO

## Cómo se define VSO en este proyecto

En este repositorio los recursos de Vault Secrets Operator no salen de una umbrella chart.

Se definen directamente como YAMLs en el repo GitOps. El ejemplo real actual está en:

- `gitops/platform/jobs/keycloak-secrets/keycloak-secrets.yaml`

La idea es simple:

1. `VaultAuth` vincula Kubernetes con un role de Vault
2. `VaultStaticSecret` lee un path KV de Vault
3. VSO crea o actualiza un `Secret` nativo de Kubernetes

## Keycloak

### Qué hace `VaultAuth`

`VaultAuth` enlaza:

- namespace Kubernetes: `keycloak`
- `ServiceAccount`: `default`
- role de Vault: `keycloak`
- mount de auth: `kubernetes`

Ese role se crea desde el seed script:

- `./scripts/05-seed-vault.sh dev`
- `./scripts/05-seed-vault.sh pro`

### Qué hacen los `VaultStaticSecret`

Hay dos sincronizaciones:

- `keycloak-db-secret-sync`
- `keycloak-admin-secret-sync`

Ambas leen el path `dev/keycloak` sobre el mount `secret` y generan dos `Secret` distintos:

- `keycloak-db-secret`
- `keycloak-admin-secret`

## YAML real del repo

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: keycloak-vault-auth
  namespace: keycloak
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: keycloak
    serviceAccount: default
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: keycloak-db-secret-sync
  namespace: keycloak
spec:
  type: kv-v2
  mount: secret
  path: dev/keycloak
  destination:
    name: keycloak-db-secret
    create: true
    transformation:
      templates:
        password:
          text: '{{ .Secrets.db_password }}'
        postgres-password:
          text: '{{ .Secrets.db_password }}'
  refreshAfter: 60s
  vaultAuthRef: keycloak-vault-auth
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: keycloak-admin-secret-sync
  namespace: keycloak
spec:
  type: kv-v2
  mount: secret
  path: dev/keycloak
  destination:
    name: keycloak-admin-secret
    create: true
    transformation:
      templates:
        admin-password:
          text: '{{ .Secrets.admin_password }}'
  refreshAfter: 60s
  vaultAuthRef: keycloak-vault-auth
```

## Correspondencia con Vault

Para `dev`, ese YAML espera este secreto en Vault:

```bash
vault kv get secret/dev/keycloak
```

Claves mínimas:

- `db_password`
- `admin_password`

Para `pro`, el patrón es el mismo cambiando el path a:

```text
secret/pro/keycloak
```

## Patrón futuro para Velero

Velero todavía no está implementado en este repo, pero seguirá el mismo patrón:

1. `VaultAuth`
2. `VaultStaticSecret`
3. `Secret` de Kubernetes consumido por Velero

Path previsto en Vault:

- `secret/dev/velero/aws`
- `secret/pro/velero/aws`

La diferencia respecto a Keycloak será la transformación del contenido, porque Velero necesita una clave `cloud` con formato INI para el plugin AWS.
