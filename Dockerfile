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

FROM --platform=$BUILDPLATFORM public.ecr.aws/docker/library/golang:1.26.1@sha256:c7e98cc0fd4dfb71ee7465fee6c9a5f079163307e4bf141b336bb9dae00159a5 AS builder
ARG PKG
ENV PKG=${PKG}
WORKDIR /go/src/${PKG}
RUN go env -w GOCACHE=/gocache GOMODCACHE=/gomodcache
COPY go.* .
ARG GOPROXY
RUN --mount=type=cache,target=/gomodcache go mod download
COPY . .
ARG TARGETOS
ARG TARGETARCH
ARG VERSION
ARG COMMIT
ARG DATE
ARG GOEXPERIMENT
RUN --mount=type=cache,target=/gomodcache --mount=type=cache,target=/gocache OS=$TARGETOS ARCH=$TARGETARCH make build

FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal@sha256:0051b1aa8e8023cd02ce41aace90dc05dcc68e9e85e44bb0abe46f25c3b2c962 as linux-al2023
ARG PKG
ENV PKG=${PKG}
COPY --from=builder /go/src/${PKG}/bin/kscu /bin/kscu
ENTRYPOINT ["/bin/kscu"]