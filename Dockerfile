ARG GO_IMAGE=rancher/hardened-build-base:v1.26.5b1
ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder
# copy xx scripts to the build stage
COPY --from=xx / /
RUN apk add --no-cache file make git clang lld
ARG TARGETPLATFORM
RUN set -x && xx-apk --no-cache add musl-dev gcc lld

ARG PKG
ARG TAG
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN go mod download

# cross-compilation setup
ARG TARGETARCH
RUN xx-go --wrap && \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o "/usr/local/bin/goldmane" ./goldmane/cmd
RUN xx-verify --static /usr/local/bin/goldmane
RUN if [ "$(xx-info arch)" = "amd64" ]; then \
        go-assert-boring.sh /usr/local/bin/goldmane; \
    fi

FROM ${BCI_IMAGE} AS hardened-calico-goldmane
LABEL org.opencontainers.image.description="Calico Goldmane flow aggregator"
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/local/bin/goldmane /goldmane
ENTRYPOINT ["/goldmane"]
