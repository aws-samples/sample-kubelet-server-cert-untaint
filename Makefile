# Copyright 2026 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# =============================================================================
# Configuration Fixed
# =============================================================================
BINARY=kscu
NAME=kubelet-server-cert-untaint
PKG=youwalther65/$(NAME)

# =============================================================================
# Configuration Variables
# =============================================================================

# Docker registry configuration
# Set IMAGE_REGISTRY to push to a custom registry (e.g., ghcr.io/aws, your-account.dkr.ecr.region.amazonaws.com)
IMAGE_REGISTRY ?= public.ecr.aws/g3x2k6s4
IMAGE_REPOSITORY ?= kscu
IMAGE_TAG ?= 1.5

# Compute IMAGE_URI based on whether registry is set
ifdef IMAGE_REGISTRY
    IMAGE_URI ?= $(IMAGE_REGISTRY)/$(IMAGE_REPOSITORY):$(IMAGE_TAG)
else
    IMAGE_URI ?= $(IMAGE_REPOSITORY):$(IMAGE_TAG)
endif

# must match Chart.yaml version !!!
VERSION ?= 1.1.0

IMAGE ?= public.ecr.aws/g3x2k6s4/kscu
TAG ?= 1.5
OSVERSION ?= al2023
GO ?= go
OS ?= $(shell $(GO) env GOHOSTOS)
ARCH ?= $(shell $(GO) env GOHOSTARCH)


GIT_COMMIT ?= $(shell git rev-parse HEAD)
BUILD_DATE ?= $(shell date -u -Iseconds)
LDFLAGS ?= "-X ${PKG}/pkg/config.taintremoverVersion=${VERSION} -X ${PKG}/pkg/config.gitCommit=${GIT_COMMIT} -X ${PKG}/pkg/config.buildDate=${BUILD_DATE} -s -w"

ALL_OS ?= linux
ALL_ARCH_linux ?= amd64 arm64
ALL_OSVERSION_linux ?= al2023
ALL_OS_ARCH_OSVERSION_linux = $(foreach arch, $(ALL_ARCH_linux), $(foreach osversion, ${ALL_OSVERSION_linux}, linux-$(arch)-${osversion}))
ALL_OS_ARCH_OSVERSION = $(foreach os, $(ALL_OS), ${ALL_OS_ARCH_OSVERSION_${os}})

EKS_AUTO_MODE = $(shell kubectl get crd nodeclasses.eks.amazonaws.com 1>/dev/null 2>&1; echo $$?)

LOG_LEVEL ?= 4
NODE_NAME ?= "i-0abcdef0123456789"

CHART_DIR ?= charts/$(NAME)
CHART_OUTPUT_DIR ?= build/charts
HELM_RELEASE ?= "$(NAME)
HELM_RELEASE_NAMESPACE ?= "kube-system"
HELM_VALUES_FILE = "charts/$(NAME)/sample-values.yaml"
HELM_REGISTRY ?= $(IMAGE_REGISTRY)
# Additional helm flags (user can override)
HELM_EXTRA_FLAGS ?=
# Helm flags for template rendering and deployment
HELM_FLAGS := --namespace $(HELM_RELEASE_NAMESPACE) \
              $(HELM_EXTRA_FLAGS)

# split words on hyphen, access by 1-index
word-hyphen = $(word $2,$(subst -, ,$1))

.EXPORT_ALL_VARIABLES:

# =============================================================================
# Help Target
# =============================================================================

.PHONY: help
help: ## Show this help message
	@echo "Kubelet Server Certificate Untaint (kscu) - Available Targets"
	@echo ""
	@echo "Development:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(build|fmt|vet|clean)' | grep -v 'docker-build' | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Docker Operations:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(docker-)' | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Deployment:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(install|install-|uninstall-)' | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Helm Operations:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(helm-)' | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration Variables:"
	@echo "  IMAGE_REGISTRY.        Container registry URL (default: empty, local only)"
	@echo "  IMAGE_REPOSITORY.      Image repository name (default: eks-node-monitoring-agent)"
	@echo "  IMAGE_TAG              Image tag (default: latest)"
	@echo "  HELM_RELEASE           helm release name"
	@echo "  HELM_RELEASE_NAMESPACE helm release namespace"
	@echo "  HELM_VALUES_FILE       helm values YAML file"
	@echo "  HELM_EXTRA_FLAGS       Additional flags for helm commands"
	@echo ""
	@echo "Examples:"
	@echo "  make docker-build IMAGE_REGISTRY=your-account.dkr.ecr.us-west-2.amazonaws.com"
	@echo "  make docker-build IMAGE_REGISTRY=your-account.dkr.ecr.us-west-2.amazonaws.com IMAGE_TAG=v1.0.0"
	@echo "  make docker-build IMAGE_REGISTRY=your-account.dkr.ecr.us-west-2.amazonaws.com GOBUILDARGS='-race'"
	@echo ""
	@echo "  make deploy install-kscu-helm HELM_VALUES_FILE='your-values-file.yaml'"
	@echo "  make deploy install-kscu-helm HELM_EXTRA_FLAGS='--set nodeAgent.image.tag=v1.0.0'"

.PHONY: build
build: mod-tidy fmt vet ## Build Go code
	GO_ENABLED=0 GOOS=$(OS) GOARCH=$(ARCH) $(GO) build -mod=readonly -ldflags ${LDFLAGS} -o bin/$(BINARY) ./cmd/

.PHONY: mod-tidy
mod-tidy: ## Tidy Go modules
	$(GO) mod tidy

.PHONY: fmt
fmt: ## Format Go code
	$(GO) fmt ./...

.PHONY: vet
vet: ## Run go vet
	$(GO) vet ./...

.PHONY: run
run: ## Run Go code locally
	GO_ENABLED=0 GOOS=$(OS) GOARCH=$(ARCH) $(GO) run ./cmd/main.go -node-name $(NODE_NAME) -v $(LOG_LEVEL)

.PHONY: clean
clean: ## Clean build artifacts
	$(GO) clean ./...
	rm -rf build/
	rm -rf bin/

# =============================================================================
# Docker Targets
# =============================================================================

.PHONY: docker-build
docker-build: docker-login all-image-registry push-manifest ## Build and push multi-arch Docker image (requires IMAGE_REGISTRY)

.PHONY: docker-login
docker-login:
	@if [ ! -f Dockerfile ]; then \
		echo "Error: Dockerfile not found in repository root"; \
		echo "Please ensure Dockerfile exists before building"; \
		exit 1; \
	fi
	@if [ -z "$(IMAGE_REGISTRY)" ]; then \
		echo "Error: IMAGE_REGISTRY is required (multi-arch images must be pushed to a registry)"; \
		echo "Usage: make docker-build IMAGE_REGISTRY=your-registry.com"; \
		exit 1; \
	fi
	@# Handle ECR authentication if registry looks like ECR
	@if echo "$(IMAGE_REGISTRY)" | grep -q "dkr\.ecr\."; then \
		echo "Detected AWS private ECR registry, attempting authentication..."; \
		REGION=$$(echo "$(IMAGE_REGISTRY)" | sed -n 's/.*\.ecr\.\([^.]*\)\.amazonaws\.com.*/\1/p'); \
		aws ecr get-login-password --region $$REGION | docker login --username AWS --password-stdin $(IMAGE_REGISTRY) || \
			(echo "ECR login failed. Ensure AWS credentials are configured." && exit 1); \
		aws ecr describe-repositories --repository-names $(IMAGE_REPOSITORY) --region $$REGION >/dev/null 2>&1 || \
			aws ecr create-repository --repository-name $(IMAGE_REPOSITORY) --region $$REGION; \
	fi
	@if echo "$(IMAGE_REGISTRY)" | grep -q "public\.ecr\."; then \
		echo "Detected AWS public ECR registry, attempting authentication..."; \
		REGION="us-east-1"; \
		aws ecr-public get-login-password --region $$REGION | docker login --username AWS --password-stdin $(IMAGE_REGISTRY) || \
			(echo "ECR login failed. Ensure AWS credentials are configured." && exit 1); \
		aws ecr-public describe-repositories --repository-names $(IMAGE_REPOSITORY) --region $$REGION >/dev/null 2>&1 || \
			aws ecr-public create-repository --repository-name $(IMAGE_REPOSITORY) --region $$REGION; \
	fi

.PHONY: all-image-registry
all-image-registry: $(addprefix sub-image-,$(ALL_OS_ARCH_OSVERSION))

sub-image-%:
	$(MAKE) OS=$(call word-hyphen,$*,1) ARCH=$(call word-hyphen,$*,2) OSVERSION=$(call word-hyphen,$*,3) image
	
.PHONY: image
image:
	BUILDX_NO_DEFAULT_ATTESTATIONS=1 docker buildx build \
		--platform=$(OS)/$(ARCH) \
		--progress=plain \
		--target=$(OS)-$(OSVERSION) \
		--output=type=registry \
		-t=$(IMAGE_URI)-$(OS)-$(ARCH)-$(OSVERSION) \
		--build-arg=GOPROXY=$(GOPROXY) \
		--build-arg=VERSION=$(VERSION) \
		--build-arg=PKG=$(PKG) \
		$(DOCKER_EXTRA_ARGS) \
		.
		
.PHONY: create-manifest
create-manifest: all-image-registry
# sed expression:
# LHS: match 0 or more not space characters
# RHS: replace with $(IMAGE):$(TAG)-& where & is what was matched on LHS
	docker manifest create --amend $(IMAGE_URI) $(shell echo $(ALL_OS_ARCH_OSVERSION) | sed -e "s~[^ ]*~$(IMAGE_URI)\-&~g")

.PHONY: push-manifest
push-manifest: create-manifest
	docker manifest push --purge $(IMAGE_URI)

# =============================================================================
# Deployment Target
# =============================================================================

.PHONY: install-kscu
install-kscu: ## Deploys RBAC and DaemonSet using kubectl
	@echo "\tInstalling RBAC and DaemonSet"
	kubectl apply -f deploy/kubernetes/rbac.yaml
	kubectl apply -f deploy/kubernetes/daemonset.yaml

.PHONY: install-kscu-helm
install-kscu-helm: ## Deploys RBAC and DaemonSet using helm
	helm upgrade --install $(HELM_RELEASE)  \
	charts/kubelet-server-cert-untaint -f $(HELM_VALUES_FILE) -n $(HELM_RELEASE_NAMESPACE)

.PHONY: install-sample
install-sample: ## Deloys sample NodePool and Deployment
	@echo "\tInstalling Nodepool \"sample\""
ifeq ($(EKS_AUTO_MODE),0)
	kubectl apply -f deploy/karpenter/sample-nodepool-auto-mode.yaml
else
	kubectl apply -f deploy/karpenter/sample-nodepool.yaml
endif
	@echo "\tInstalling Deployment \"sample-deploy\""
	kubectl apply -f deploy/karpenter/sample-deploy.yaml

.PHONY: install
install: install-kscu install-sample ## Deploys RBAC, DaemonSet, sample NodePool and Deployment using kubectl

.PHONY: uninstall ## Uninstalls RBAC, DaemonSet, sample NodePool and Deployment using kubectl
uninstall: uninstall-kscu uninstall-sample

.PHONY: uninstall-kscu ## Uninstalls RBAC and DaemonSet using kubectl
uninstall-kscu:
	@echo "\tRemoving RBAC and DaemonSet"
	-kubectl delete -f deploy/kubernetes/daemonset.yaml
	-kubectl delete -f deploy/kubernetes/rbac.yaml

.PHONY: uninstall-kscu-helm
uninstall-kscu-helm: ## Uninstalls Helm release
	helm uninstall $(HELM_RELEASE) -n $(HELM_RELEASE_NAMESPACE)

.PHONY: uninstall-sample
uninstall-sample: ## Uninstalls sample NodePool and Deployment
	@echo "\tRemoving Deployment \"sample-deploy\""
	-kubectl delete -f deploy/karpenter/sample-deploy.yaml
	@echo "\tRemoving Nodepool \"sample\""
ifeq ($(EKS_AUTO_MODE),0)
	-kubectl delete -f deploy/karpenter/sample-nodepool-auto-mode.yaml
else
	-kubectl delete -f deploy/karpenter/sample-nodepool.yaml
endif

# =============================================================================
# Helm Targets
# =============================================================================

.PHONY: helm-login
helm-login:
	@# Handle ECR authentication if registry looks like ECR
	@if echo "$(HELM_REGISTRY)" | grep -q "dkr\.ecr\."; then \
		echo "Detected AWS private ECR registry, attempting authentication..."; \
		REGION=$$(echo "$(HELM_REGISTRY)" | sed -n 's/.*\.ecr\.\([^.]*\)\.amazonaws\.com.*/\1/p'); \
		aws ecr get-login-password --region $$REGION | docker login --username AWS --password-stdin $(HELM_REGISTRY) || \
			(echo "ECR login failed. Ensure AWS credentials are configured." && exit 1); \
		aws ecr describe-repositories --repository-names $(NAME) --region $$REGION >/dev/null 2>&1 || \
			aws ecr create-repository --repository-name $(NAME) --region $$REGION; \
	fi
	@if echo "$(HELM_REGISTRY)" | grep -q "public\.ecr\."; then \
		echo "Detected AWS public ECR registry, attempting authentication..."; \
		REGION="us-east-1"; \
		aws ecr-public get-login-password --region $$REGION | docker login --username AWS --password-stdin $(HELM_REGISTRY) || \
			(echo "ECR login failed. Ensure AWS credentials are configured." && exit 1); \
		aws ecr-public describe-repositories --repository-names $(NAME) --region $$REGION >/dev/null 2>&1 || \
			aws ecr-public create-repository --repository-name $(NAME) --region $$REGION; \
	fi

.PHONY: helm-lint
helm-lint: ## Lint Helm chart for errors
	@if command -v helm >/dev/null 2>&1; then \
		helm lint $(CHART_DIR); \
	else \
		echo "Helm not available, skipping helm-lint"; \
	fi

.PHONY: helm-template
helm-template: ## Render Helm chart templates to stdout
	@if command -v helm >/dev/null 2>&1; then \
		helm template eks-node-monitoring-agent $(CHART_DIR) $(HELM_FLAGS); \
	else \
		echo "Helm not available, skipping helm-template"; \
	fi

.PHONY: helm-package
helm-package: ## Package Helm chart into .tgz archive
	@if command -v helm >/dev/null 2>&1; then \
		$(MAKE) helm-lint; \
		mkdir -p $(CHART_OUTPUT_DIR); \
		helm package $(CHART_DIR) --destination $(CHART_OUTPUT_DIR); \
		echo "Chart packaged to $(CHART_OUTPUT_DIR)/"; \
	else \
		echo "Helm not available, skipping helm-package"; \
	fi

.PHONY: helm-push
helm-push: helm-login helm-package ## Push Helm pakage to OCI registry
	helm push $(CHART_OUTPUT_DIR)/$(NAME)-$(VERSION).tgz oci://$(HELM_REGISTRY)
