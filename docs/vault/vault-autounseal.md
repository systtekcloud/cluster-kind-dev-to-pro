# Vault Auto-unseal con AWS KMS

## Alcance

Esta guía es solo referencia para una evolución futura a producción real en EKS.

No aplica al despliegue actual en kind:

- `dev` usa init y unseal manual
- `pro` en kind también usa init manual y unseal manual sobre Raft

Si `pro` pasa a EKS, el sitio correcto para configurar auto-unseal será:

- `components/vault/pro/values-vault.yaml`

## Idea base

Con auto-unseal:

1. `vault operator init` sigue siendo obligatorio
2. Vault cifra internamente su material de sellado con AWS KMS
3. tras un reinicio, Vault se desella solo

Esto elimina el unseal manual recurrente, pero no elimina el `init` inicial.

## Dónde va la configuración

En este repo, el bloque `seal "awskms"` debe ir dentro de:

- `server.ha.raft.config`

No va en overlays de un chart externo ni en values heredados de otro proyecto.

## Ejemplo de configuración

Fragmento orientativo para `components/vault/pro/values-vault.yaml`:

```yaml
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        ui = true

        listener "tcp" {
          tls_disable = 1
          address         = "[::]:8200"
          cluster_address = "[::]:8201"
        }

        storage "raft" {
          path = "/vault/data"

          retry_join {
            leader_api_addr = "http://vault-0.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-1.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-2.vault-internal:8200"
          }
        }

        seal "awskms" {
          region     = "eu-west-1"
          kms_key_id = "arn:aws:kms:eu-west-1:<account-id>:key/<key-id>"
        }

        service_registration "kubernetes" {}

  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/vault-irsa
```

## Requisitos mínimos en AWS

### KMS

Hace falta una KMS Key dedicada para Vault.

Permisos mínimos:

- `kms:Encrypt`
- `kms:Decrypt`
- `kms:DescribeKey`

### IRSA

La opción recomendada en EKS es IRSA sobre la `ServiceAccount` de Vault.

La anotación va en `server.serviceAccount.annotations`:

```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/vault-irsa
```

## Init con auto-unseal

Aunque exista auto-unseal, el primer `init` sigue siendo manual:

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3
```

Con AWS KMS:

- no operas con unseal keys normales en el día a día
- pasas a usar recovery keys para recuperación
- el root token sigue siendo crítico

## Verificación

Después de desplegar y hacer `init`:

```bash
kubectl exec -n vault vault-0 -- vault status
```

Debe verse:

- `Initialized: true`
- `Sealed: false`
- `Seal Type: awskms`

Prueba de reinicio:

```bash
kubectl delete pod -n vault vault-0
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=300s
kubectl exec -n vault vault-0 -- vault status
```

Si auto-unseal está bien configurado, el pod vuelve con `Sealed: false` sin ejecutar `vault operator unseal`.
