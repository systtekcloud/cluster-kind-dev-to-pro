# Velero

## Estado

Velero es un componente planificado, no implementado aún en este repositorio.

Cuando se añada, seguirá el mismo patrón que Keycloak:

```text
Vault -> VaultStaticSecret (VSO) -> Secret de Kubernetes -> Velero
```

Paths previstos en Vault:

- `secret/dev/velero/aws`
- `secret/pro/velero/aws`

## Patrón previsto

Velero no consume secretos directamente desde Vault. Necesita un `Secret` de Kubernetes.

El flujo esperado será:

1. guardar credenciales S3 en Vault
2. definir `VaultAuth` y `VaultStaticSecret` en GitOps
3. transformar el secreto al formato `cloud`
4. hacer que Velero consuma ese `Secret`

Ejemplo del contenido que normalmente espera el plugin AWS:

```ini
[default]
aws_access_key_id=...
aws_secret_access_key=...
```

## Recursos VSO previstos

El patrón será equivalente al de Keycloak, pero apuntando al path de Velero.

Referencia de destino:

- `VaultAuth` en el namespace donde corra Velero
- `VaultStaticSecret` leyendo `dev/velero/aws` o `pro/velero/aws`
- `Secret` de Kubernetes con la clave `cloud`

## Cambio pendiente en `seed-secrets.sh`

Para soportar Velero habrá que extender:

- `components/vault/setup/seed-secrets.sh`

Fragmento orientativo:

```bash
echo ""
echo "=== Credenciales S3 de Velero ==="
read -r -p "Velero AWS access key id: " VELERO_ACCESS_KEY_ID
read -r -s -p "Velero AWS secret access key: " VELERO_SECRET_ACCESS_KEY
echo

if [[ -n "$VELERO_ACCESS_KEY_ID" && -n "$VELERO_SECRET_ACCESS_KEY" ]]; then
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
    TARGET="$TARGET" \
    VELERO_ACCESS_KEY_ID="$VELERO_ACCESS_KEY_ID" \
    VELERO_SECRET_ACCESS_KEY="$VELERO_SECRET_ACCESS_KEY" \
    sh -c 'vault kv put secret/${TARGET}/velero/aws \
      access_key_id="${VELERO_ACCESS_KEY_ID}" \
      secret_access_key="${VELERO_SECRET_ACCESS_KEY}"' >/dev/null
fi
```

## Referencia conceptual

### CSI vs File System Backup

Velero puede proteger volúmenes de dos formas:

- snapshots CSI
- File System Backup (`node-agent` / Kopia)

Regla práctica:

- si el storage del clúster soporta `VolumeSnapshot`, CSI suele ser la opción preferida
- si no hay snapshots nativos o se necesita portabilidad máxima, FSB es la alternativa

### IRSA y credenciales

En AWS hay dos modelos habituales:

- credenciales estáticas en un `Secret`
- IRSA sobre la `ServiceAccount` de Velero

Si Velero acaba desplegándose en EKS, IRSA será normalmente la opción preferida. Si se mantiene en kind o en un entorno S3-compatible sin identidad cloud, el camino natural será `Vault -> VSO -> Secret`.

### Qué no forma parte de este repo ahora mismo

No hay todavía:

- chart de Velero integrado
- `VaultAuth`/`VaultStaticSecret` de Velero en GitOps
- credentials secret generado por VSO
- documentación operativa de buckets, schedules o restores específica de este proyecto
