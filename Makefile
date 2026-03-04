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

VERSION?=1.1
BINARY=kscu
IMAGE?=public.ecr.aws/g3x2k6s4/kscu
TAG?=1.5
OSVERSION?=al2023
OS?=$(shell go env GOHOSTOS)
ARCH?=$(shell go env GOHOSTARCH)
PKG=youwalther65/kubelet-server-cert-untaint
GIT_COMMIT?=$(shell git rev-parse HEAD)
BUILD_DATE?=$(shell date -u -Iseconds)
LDFLAGS?="-X ${PKG}/pkg/config.taintremoverVersion=${VERSION} -X ${PKG}/pkg/config.gitCommit=${GIT_COMMIT} -X ${PKG}/pkg/config.buildDate=${BUILD_DATE} -s -w"

ALL_OS?=linux windows
ALL_ARCH_linux?=amd64 arm64
ALL_OSVERSION_linux?=al2023
ALL_OS_ARCH_OSVERSION_linux=$(foreach arch, $(ALL_ARCH_linux), $(foreach osversion, ${ALL_OSVERSION_linux}, linux-$(arch)-${osversion}))
ALL_OS_ARCH_OSVERSION=$(foreach os, $(ALL_OS), ${ALL_OS_ARCH_OSVERSION_${os}})

EKS_AUTO_MODE=$(shell kubectl get crd nodeclasses.eks.amazonaws.com 1>/dev/null 2>&1; echo $$?)

HELM_RELEASE="kubelet-server-cert-untaint"
HELM_RELEASE_NAMESPACE="kube-system"
HELM_SAMPLE_VALUES_FILE="charts/kubelet-server-cert-untaint/sample-values.yaml"

# split words on hyphen, access by 1-index
word-hyphen = $(word $2,$(subst -, ,$1))

.EXPORT_ALL_VARIABLES:

.PHONY: build
build:
	GO_ENABLED=0 GOOS=$(OS) GOARCH=$(ARCH) go build -mod=readonly -ldflags ${LDFLAGS} -o bin/$(BINARY) ./cmd/

.PHONY: docker-build
docker-build: all-image-registry push-manifest

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
		-t=$(IMAGE):$(TAG)-$(OS)-$(ARCH)-$(OSVERSION) \
		--build-arg=GOPROXY=$(GOPROXY) \
		--build-arg=VERSION=$(VERSION) \
		$(DOCKER_EXTRA_ARGS) \
		.
		
.PHONY: create-manifest
create-manifest: all-image-registry
# sed expression:
# LHS: match 0 or more not space characters
# RHS: replace with $(IMAGE):$(TAG)-& where & is what was matched on LHS
	docker manifest create --amend $(IMAGE):$(TAG) $(shell echo $(ALL_OS_ARCH_OSVERSION) | sed -e "s~[^ ]*~$(IMAGE):$(TAG)\-&~g")

.PHONY: push-manifest
push-manifest: create-manifest
	docker manifest push --purge $(IMAGE):$(TAG)

.PHONY: install-kscu
install-kscu:
	@echo "\tInstalling RBAC and DaemonSet"
	kubectl apply -f deploy/kubernetes/rbac.yaml
	kubectl apply -f deploy/kubernetes/daemonset.yaml

.PHONY: install-kscu-helm
install-kscu-helm:
	helm upgrade --install $(HELM_RELEASE)  \
	charts/kubelet-server-cert-untaint -f $(HELM_SAMPLE_VALUES_FILE) -n $(HELM_RELEASE_NAMESPACE)

.PHONY: install-sample
install-sample:
	@echo "\tInstalling Nodepool \"sample\""
ifeq ($(EKS_AUTO_MODE),0)
	kubectl apply -f deploy/karpenter/sample-nodepool-auto-mode.yaml
else
	kubectl apply -f deploy/karpenter/sample-nodepool.yaml
endif
	@echo "\tInstalling Deployment \"sample-deploy\""
	kubectl apply -f deploy/karpenter/sample-deploy.yaml

.PHONY: install
install: install-kscu install-sample

.PHONY: uninstall
uninstall: uninstall-kscu uninstall-sample

.PHONY: uninstall-kscu
uninstall-kscu:
	@echo "\tRemoving RBAC and DaemonSet"
	-kubectl delete -f deploy/kubernetes/daemonset.yaml
	-kubectl delete -f deploy/kubernetes/rbac.yaml

.PHONY: uninstall-kscu-helm
uninstall-kscu-helm:
	helm uninstall $(HELM_RELEASE) -n $(HELM_RELEASE_NAMESPACE)

.PHONY: uninstall-sample
uninstall-sample:
	@echo "\tRemoving Deployment \"sample-deploy\""
	-kubectl delete -f deploy/karpenter/sample-deploy.yaml
	@echo "\tRemoving Nodepool \"sample\""
ifeq ($(EKS_AUTO_MODE),0)
	-kubectl delete -f deploy/karpenter/sample-nodepool-auto-mode.yaml
else
	-kubectl delete -f deploy/karpenter/sample-nodepool.yaml
endif


.PHONY: clean
clean:
	rm -rf bin/