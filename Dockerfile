FROM registry.redhat.io/ubi9/go-toolset:latest as golang_builder
ARG BUILDPLATFORM
ARG ARCH

USER root

COPY yarn-install . 
RUN npm install --offline
RUN ln -s $PWD/node_modules/yarn/bin/yarn /usr/local/bin/yarn

RUN yum install -y systemd-devel \
  && dnf module reset -y  nodejs \
  && node -v \
  && yarn -v

RUN go env -w GOBIN='/go/bin'

ENV CONTROLLER_GEN_VERSION v0.9.2

RUN cp /cachi2/output/deps/generic/helm-linux-${BUILDPLATFORM} /usr/bin/helm

#RUN GOFLAGS="-mod=mod" go install sigs.k8s.io/controller-tools/cmd/controller-gen@$CONTROLLER_GEN_VERSION \
# && GOFLAGS="-mod=mod" go install github.com/mitchellh/gox@v1.0.1                                         \
# && GOFLAGS="-mod=mod" go install github.com/tcnksm/ghr@v0.15.0                                           \
# && GOFLAGS="-mod=mod" go install github.com/grafana/tanka/cmd/tk@v0.22.1                                 \
# && GOFLAGS="-mod=mod" go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@v0.5.1                \
# && GOFLAGS="-mod=mod" go install github.com/google/go-jsonnet/cmd/jsonnet@v0.18.0                        \
# && GOFLAGS="-mod=mod" go install github.com/golang/protobuf/protoc-gen-go@v1.3.1                         \
# && GOFLAGS="-mod=mod" go install github.com/gogo/protobuf/protoc-gen-gogoslick@v1.3.0                    \
# && GOFLAGS="-mod=mod" go install github.com/gogo/protobuf/gogoproto/...@v1.3.0                           \
# && GOFLAGS="-mod=mod" go install github.com/ahmetb/gen-crd-api-reference-docs@v0.3.1-0.20220618162802-424739b250f5 \
# && GOFLAGS="-mod=mod" go install github.com/norwoodj/helm-docs/cmd/helm-docs@v1.11.0

COPY . /src
WORKDIR /src/alloy/internal/web/ui/
#RUN yarn install --offline --frozen-lockfile --ignore-scripts && yarn run build
RUN yarn install --offline --frozen-lockfile --ignore-scripts && yarn run --offline build

WORKDIR /src/alloy

RUN GO_TAGS="builtinassets promtail_journal_enabled" GOOS="linux" GOARCH= GOARM= make alloy

# Stage 2
FROM registry.access.redhat.com/ubi10-minimal:latest

ARG UID="473"
ARG USERNAME="alloy"

RUN microdnf update -y

RUN microdnf install -y tzdata shadow-utils

COPY --from=golang_builder --chown=${UID}:${UID} /src/alloy/build/alloy /bin/alloy
COPY --chown=${UID}:${UID} ./alloy/example-config.alloy /etc/alloy/config.alloy

RUN groupadd --gid $UID $USERNAME \
    && useradd -m -u $UID -g $UID $USERNAME \
    && mkdir -p /var/lib/alloy/data \
    && chown -R $USERNAME:$USERNAME /var/lib/alloy \
    && chmod -R 770 /var/lib/alloy

# Standard Red Hat labels
LABEL com.redhat.component="alloy-container"
LABEL name="alloy"
LABEL version="v1.10.1-1"
LABEL summary="Provides alloy container"
LABEL io.k8s.display-name="Alloy container"
LABEL maintainer="Rakshitha Kamath <rkamath@redhat.com>"
LABEL description="Grafana Alloy is an open source OpenTelemetry Collector distribution with built-in Prometheus pipelines and support for metrics, logs, traces, and profiles."
LABEL io.k8s.description="Grafana Alloy is an open source OpenTelemetry Collector distribution with built-in Prometheus pipelines and support for metrics, logs, traces, and profiles."
LABEL io.openshift.tags="Alloy container"

# The CPE (Common Platform Enumeration) identifier for Ceph.
LABEL cpe=cpe:/a:redhat:ceph_storage:9::el10

# Add Creation date label
LABEL org.opencontainers.image.created="${BUILD_DATE}"

ENTRYPOINT ["/bin/alloy"]
ENV ALLOY_DEPLOY_MODE=docker
CMD ["run", "/etc/alloy/config.alloy", "--storage.path=/var/lib/alloy/data"]
