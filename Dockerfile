FROM registry.redhat.io/ubi9/go-toolset:latest as golang_builder
ARG TARGETARCH

USER root

ENV PATH="/usr/bin/go:$PATH"
ENV GOPATH='/opt/app-root/src/go'
ENV GOCACHE='/opt/app-root/src/.cache/go-build'

# Install Helm CLI (using prefetched modules)
COPY . /src
WORKDIR /src

# This one will download the deps in the alloy-container folder's go.mod
RUN if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; fi && \
    go mod download

# Build helm binary using go
RUN if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; fi && \
    go build -o /usr/bin/helm helm.sh/helm/v3/cmd/helm

# Install yarn using npm package manager.
COPY yarn-install . 
RUN npm install --offline
RUN ln -s $PWD/node_modules/yarn/bin/yarn /usr/local/bin/yarn

RUN yum install -y systemd-devel hostname \
  && dnf module reset -y nodejs \
  && node -v \
  && yarn -v

WORKDIR /src/alloy/internal/web/ui/
RUN yarn install --offline --frozen-lockfile --ignore-scripts && yarn run --offline build

WORKDIR /src/alloy

# This one will download the deps in the alloy subfolder's go.mod
RUN if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; fi && \
    go mod download

# We are only building for linux OS so we don't have to use GO_TAG="netgo"
RUN GO_TAGS="builtinassets promtail_journal_enabled" GOOS="linux" GOARCH=$TARGETARCH GOARM= RELEASE_BUILD=1 make alloy

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

COPY alloy/LICENSE /licenses/

# Standard Red Hat labels
LABEL com.redhat.component="alloy-container"
LABEL name=rhceph/alloy-rhel10
LABEL version="v1.10.2"
LABEL summary="Provides alloy container"
LABEL io.k8s.display-name="Alloy container"
LABEL maintainer="Rakshitha Kamath <rkamath@redhat.com>"
LABEL description="Grafana Alloy is an open source OpenTelemetry Collector distribution with built-in Prometheus pipelines and support for metrics, logs, traces, and profiles."
LABEL io.k8s.description="Grafana Alloy is an open source OpenTelemetry Collector distribution with built-in Prometheus pipelines and support for metrics, logs, traces, and profiles."
LABEL io.openshift.tags="Alloy container"
LABEL vcs-url="https://github.com/ibmstorage/alloy-container.git"
LABEL org.opencontainers.image.source="https://github.com/ibmstorage/alloy-container.git"

# The CPE (Common Platform Enumeration) identifier for Ceph.
LABEL cpe=cpe:/a:redhat:ceph_storage:9.2::el10

# Z-stream indicator
LABEL Z-VERSION="9.2"

ENTRYPOINT ["/bin/alloy"]
ENV ALLOY_DEPLOY_MODE=docker
CMD ["run", "/etc/alloy/config.alloy", "--storage.path=/var/lib/alloy/data"]
