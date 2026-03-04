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

FROM --platform=$BUILDPLATFORM public.ecr.aws/docker/library/golang:1.26@sha256:c83e68f3ebb6943a2904fa66348867d108119890a2c6a2e6f07b38d0eb6c25c5 AS builder
WORKDIR /go/src/github.com/youwalther65/kubelet-server-cert-untaint
RUN go env -w GOCACHE=/gocache GOMODCACHE=/gomodcache
COPY go.* .
ARG GOPROXY
RUN --mount=type=cache,target=/gomodcache go mod download
COPY . .
ARG TARGETOS
ARG TARGETARCH
ARG VERSION
ARG PKG
ARG COMMIT
ARG DATE
ARG GOEXPERIMENT
RUN --mount=type=cache,target=/gomodcache --mount=type=cache,target=/gocache OS=$TARGETOS ARCH=$TARGETARCH make

FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal@sha256:6621917fc09ad8c935aa5ccc32c933c6dec250deafae54af86e154fcd19f5ed0 as linux-al2023
COPY --from=builder /go/src/github.com/youwalther65/kubelet-server-cert-untaint/bin/kscu /bin/kscu
ENTRYPOINT ["/bin/kscu"]