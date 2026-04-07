.DEFAULT_GOAL := help

# ─── Clusters ────────────────────────────────────────────────────────────────
.PHONY: create-dev create-pro create-all delete-dev delete-pro delete-all

create-dev:
	@./scripts/create-clusters.sh dev

create-pro:
	@./scripts/create-clusters.sh pro

create-all:
	@./scripts/create-clusters.sh

delete-dev:
	@./scripts/delete-clusters.sh dev

delete-pro:
	@./scripts/delete-clusters.sh pro

delete-all:
	@./scripts/delete-clusters.sh

# ─── Base Stack (Cilium + MetalLB) ───────────────────────────────────────────
.PHONY: base-dev base-pro

base-dev:
	@./scripts/install-cni-metallb.sh dev

base-pro:
	@./scripts/install-cni-metallb.sh pro

# ─── APISIX ──────────────────────────────────────────────────────────────────
.PHONY: apisix-dev apisix-pro

apisix-dev:
	@./scripts/install-apisix.sh dev

apisix-pro:
	@./scripts/install-apisix.sh pro

# ─── ArgoCD ──────────────────────────────────────────────────────────────────
.PHONY: argocd-dev argocd-pro

argocd-dev:
	@./scripts/install-argocd.sh dev

argocd-pro:
	@./scripts/install-argocd.sh pro

# ─── Full Setup ──────────────────────────────────────────────────────────────
.PHONY: setup-dev setup-pro setup-all

setup-dev: create-dev base-dev apisix-dev
	@echo "✓ dev-cluster ready with Cilium + MetalLB + APISIX"

setup-pro: create-pro base-pro apisix-pro
	@echo "✓ pro-cluster ready with Cilium + MetalLB + APISIX"

setup-all: create-all base-dev base-pro apisix-dev apisix-pro
	@echo "✓ Both clusters ready"

# ─── GitOps Stack ────────────────────────────────────────────────────────────
.PHONY: gitops-dev gitops-pro

gitops-dev: argocd-dev
	@echo "✓ ArgoCD installed on dev"

gitops-pro: argocd-pro
	@echo "✓ ArgoCD installed on pro"

# ─── Status & Context ────────────────────────────────────────────────────────
.PHONY: status ctx-dev ctx-pro

status:
	@./scripts/status.sh

ctx-dev:
	@kubectl config use-context kind-dev-cluster
	@echo "✓ Switched to kind-dev-cluster"

ctx-pro:
	@kubectl config use-context kind-pro-cluster
	@echo "✓ Switched to kind-pro-cluster"

# ─── Help ────────────────────────────────────────────────────────────────────
.PHONY: help

help:
	@echo "Kind Clusters: dev / pro"
	@echo ""
	@echo "Clusters:"
	@echo "  make create-dev    - Crear cluster dev"
	@echo "  make create-pro    - Crear cluster pro"
	@echo "  make create-all    - Crear ambos clusters"
	@echo "  make delete-all    - Eliminar ambos clusters"
	@echo ""
	@echo "Base Stack:"
	@echo "  make base-dev      - Instalar Cilium + MetalLB en dev"
	@echo "  make base-pro      - Instalar Cilium + MetalLB en pro"
	@echo ""
	@echo "Components:"
	@echo "  make apisix-dev    - Instalar APISIX en dev"
	@echo "  make argocd-dev    - Instalar ArgoCD en dev"
	@echo ""
	@echo "Full Setup:"
	@echo "  make setup-dev     - Setup completo dev (cluster + base + apisix)"
	@echo "  make setup-pro     - Setup completo pro"
	@echo "  make setup-all     - Setup completo ambos"
	@echo ""
	@echo "GitOps:"
	@echo "  make gitops-dev    - Instalar ArgoCD en dev"
	@echo "  make gitops-pro    - Instalar ArgoCD en pro"
	@echo ""
	@echo "Utilities:"
	@echo "  make status        - Estado de clusters"
	@echo "  make ctx-dev       - Cambiar contexto a dev"
	@echo "  make ctx-pro       - Cambiar contexto a pro"
