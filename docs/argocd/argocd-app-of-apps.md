# App of Apps

## Patrón

Una Application raíz (`argo-apps-kind.yml`) apunta al repo GitOps y gestiona todas las demás Applications como manifiestos declarativos. ArgoCD sincroniza ese repo y crea o actualiza cada Application automáticamente.

```
argo-apps-kind.yml
  └── App of Apps (root)
        ├── wave 1: kyverno, mongodb-operator, crossplane
        ├── wave 3: keycloak-secrets, prometheus-stack
        └── wave 4: keycloak, grafana, kargo
```

## Repo GitOps

- URL: `https://gitlab.com/eks-vcluster-platform/gitops-base-platform.git`
- Manifiesto de entrada: `argo-manifests/kind/argo-apps-kind.yml`

## Prerrequisitos antes de aplicar el App of Apps

Estos componentes **no los gestiona ArgoCD** — deben estar instalados y operativos primero:

```
./scripts/02-install-cni-metallb.sh dev
./scripts/03-install-apisix.sh dev
./scripts/05-install-vault.sh dev  →  init + unseal manual  →  ./scripts/05-seed-vault.sh dev
```

Los secrets de Vault deben existir antes de que ArgoCD sincronice wave 3 (`keycloak-secrets`), porque VSO necesita leer de Vault para crear los Kubernetes Secrets que usa Keycloak en wave 4.

## Aplicar el App of Apps

```bash
kubectl apply -f argo-manifests/kind/argo-apps-kind.yml --context kind-dev-cluster
```

## Sync waves

Las waves ordenan el despliegue respetando dependencias:

| Wave | Aplicaciones | Motivo |
|---|---|---|
| 1 | kyverno, mongodb-operator, crossplane | Operators primero — instalan CRDs que usan las apps |
| 3 | keycloak-secrets, prometheus-stack | VSO necesita Vault activo; keycloak-secrets crea los K8s Secrets |
| 4 | keycloak, grafana, kargo | Keycloak necesita los Secrets de wave 3; grafana necesita prometheus |

ArgoCD no avanza a la siguiente wave hasta que todos los recursos de la wave actual están `Healthy`.

## Multi-source

Las Applications usan multi-source para separar la chart base del overlay por entorno:

```yaml
sources:
  - repoURL: https://gitlab.com/eks-vcluster-platform/gitops-base-platform.git
    path: platform/base/keycloak
    targetRevision: HEAD
  - repoURL: https://gitlab.com/eks-vcluster-platform/gitops-base-platform.git
    path: platform/overlays/kind/keycloak
    targetRevision: HEAD
    helm:
      valueFiles:
        - $values/platform/overlays/kind/keycloak/values.yaml
```

Esto permite compartir la misma chart base y sobreescribir solo lo necesario por entorno (kind, EKS, etc.) sin duplicar manifiestos.

## AppProject

Todas las Applications pertenecen al proyecto `platform` definido en el repo GitOps:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  namespace: argo
spec:
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

El AppProject es el perímetro de seguridad de ArgoCD: controla qué repos y qué clusters/namespaces puede tocar cada conjunto de Applications.
