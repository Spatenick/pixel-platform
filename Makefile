# pixelpipe-platform -- common tasks. Run `make help`.
#
# Works with Terraform or OpenTofu:  make up ENV=dev TF=tofu

SHELL      := /bin/bash
ENV        ?= dev
REGION     ?= eu-west-2
TF         ?= terraform
TF_DIR     := infra/envs/$(ENV)
CLUSTER    := pixelpipe-$(ENV)
TF_STATE_BUCKET ?= $(shell $(TF) -chdir=infra/bootstrap output -raw state_bucket 2>/dev/null)
export TF_STATE_BUCKET AWS_REGION=$(REGION) TF

.DEFAULT_GOAL := help
.PHONY: help configure bootstrap github-vars init plan up down kubeconfig argocd grafana prometheus \
        smoke status test tf-test lint fmt local-up local-down load-test cost

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target> [ENV=dev|prod]\n\n"} /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# --- one-time setup ------------------------------------------------------------

configure: ## Fill in placeholders (GitHub repo, AWS account, your role ARN)
	./scripts/configure.sh

bootstrap: ## Create state bucket, CI roles (OIDC), ECR repos, budget  [run once]
	$(TF) -chdir=infra/bootstrap init -input=false
	$(TF) -chdir=infra/bootstrap apply
	@echo; echo "Next: make github-vars"

github-vars: ## Push bootstrap outputs into GitHub Actions variables
	./scripts/set-github-vars.sh

# --- environments -------------------------------------------------------------------

init: ## terraform init for ENV
	@test -n "$(TF_STATE_BUCKET)" || (echo "TF_STATE_BUCKET unknown -- run 'make bootstrap' first" && exit 1)
	$(TF) -chdir=$(TF_DIR) init -input=false -reconfigure \
	  -backend-config="bucket=$(TF_STATE_BUCKET)" -backend-config="region=$(REGION)"

plan: init ## terraform plan for ENV
	$(TF) -chdir=$(TF_DIR) plan

up: init ## Create/update ENV (~20-25 min from scratch)
	$(TF) -chdir=$(TF_DIR) apply
	@$(MAKE) --no-print-directory kubeconfig ENV=$(ENV)
	@echo; echo "Argo CD is now syncing the apps. Try: make status ENV=$(ENV) && make smoke ENV=$(ENV)"

down: ## Destroy ENV safely (cleans up ALBs/volumes first)
	./scripts/teardown.sh $(ENV)

# --- day-to-day --------------------------------------------------------------------

kubeconfig: ## Point kubectl at ENV's cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER) --alias $(CLUSTER)

status: ## Argo CD apps, pods and the API's public URL
	@kubectl -n argocd get applications.argoproj.io
	@echo; kubectl -n pixelpipe get pods,hpa,scaledobjects.keda.sh 2>/dev/null || kubectl -n pixelpipe get pods
	@echo; echo -n "API: http://"; kubectl -n pixelpipe get ingress pixelpipe-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null; echo

argocd: ## Open Argo CD on http://localhost:8080 (prints admin password)
	@echo "user: admin  password: $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	kubectl -n argocd port-forward svc/argo-cd-server 8080:80

grafana: ## Open Grafana on http://localhost:3000 (prints admin password)
	@echo "user: admin  password: $$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

prometheus: ## Open Prometheus on http://localhost:9090
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

smoke: ## End-to-end test: upload an image, wait for its thumbnail
	./scripts/smoke-test.sh $(ENV)

load-test: ## k6 load test against ENV (needs Docker)
	@url=$${BASE_URL:-http://$$(kubectl -n pixelpipe get ingress pixelpipe-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')}; \
	docker run --rm -i -v "$$PWD/loadtest:/scripts" -e BASE_URL=$$url grafana/k6 run /scripts/k6.js

cost: ## Monthly cost estimate for ENV (needs infracost + API key)
	infracost breakdown --path $(TF_DIR)

# --- local development -------------------------------------------------------------------

local-up: ## Run the whole app locally (Postgres + fake AWS) with Docker Compose
	docker compose up --build

local-down: ## Stop the local stack
	docker compose down -v

test: ## Run unit tests for both services
	cd apps/api && python -m pytest
	cd apps/worker && python -m pytest

tf-test: ## Offline Terraform tests (mocked providers, no AWS needed)
	$(TF) -chdir=infra/modules/environment init -backend=false -input=false
	$(TF) -chdir=infra/modules/environment test

lint: ## Lint Terraform, Python and shell
	$(TF) fmt -check -recursive infra
	tflint --recursive --config "$$PWD/.tflint.hcl" --chdir infra
	cd apps/api && ruff check . && ruff format --check .
	cd apps/worker && ruff check . && ruff format --check .
	shellcheck scripts/*.sh

fmt: ## Auto-format Terraform and Python
	$(TF) fmt -recursive infra
	cd apps/api && ruff format .
	cd apps/worker && ruff format .
