# syntax=docker/dockerfile:1.26.0@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=SecretsUsedInArgOrEnv
#####################################################
#                                                   #
#      OpenStack Keystone and Swift-All-In-One      #
#                                                   #
#####################################################

# https://releases.openstack.org/

ARG ARTIFACTORY_SERVER=
ARG ARTIFACTORY_SERVER_GHCR=

FROM        ${ARTIFACTORY_SERVER_GHCR}astral-sh/uv:0.12.9-python3.14-trixie-slim AS builder
ARG         UV_DEFAULT_INDEX=
ARG         UV_INDEX_ARTIFACTORY_USERNAME=
ENV         UV_DEFAULT_INDEX=$UV_DEFAULT_INDEX
ENV         UV_INDEX_ARTIFACTORY_USERNAME=$UV_INDEX_ARTIFACTORY_USERNAME

ENV         DEBIAN_FRONTEND=noninteractive

ENV         UV_LINK_MODE=copy
ENV         UV_PYTHON_DOWNLOADS=never

RUN         rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN         --mount=type=cache,target=/var/cache/apt,sharing=private \
            --mount=type=cache,target=/var/lib/apt,sharing=private \
            apt-get update -q \
        &&  apt-get install -yq --no-install-recommends \
                liberasurecode-dev \
                gcc \
                libc6-dev \
                libexpat1 \
                libexpat1-dev \
        &&  apt-get autoremove -yq --purge

# Install Keystone + swift + clients into a project-local venv, resolved
# from pyproject.toml + uv.lock. To regenerate the lock (e.g. after bumping
# a version in pyproject.toml's dependencies), just run `uv lock`
WORKDIR     /app

RUN         --mount=type=secret,id=artifactory_token \
            --mount=type=cache,target=/root/.cache/uv \
            --mount=type=bind,source=uv.lock,target=uv.lock \
            --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
            UV_INDEX_ARTIFACTORY_PASSWORD=$(cat /run/secrets/artifactory_token) \
            uv sync --locked --no-install-project


FROM        ${ARTIFACTORY_SERVER}python:3.14.7-slim-trixie

# TARGETARCH is populated automatically by buildx from the build/target
# platform (e.g. "amd64", "arm64") -- no --build-arg needed, and it stays
# correct under --platform linux/amd64,linux/arm64 multi-arch builds too.
# s6-overlay names its release assets by its own arch scheme (x86_64/aarch64),
# not Docker's, so remap via chained ARG pattern-substitution.
ARG         TARGETARCH
ARG         S6_ARCH=${TARGETARCH/arm64/aarch64}
ARG         S6_ARCH=${S6_ARCH/amd64/x86_64}

ENV         S6_LOGGING=1
ENV         S6_VERSION=3.2.1.0

ENV         OS_USERNAME=admin
ENV         OS_PASSWORD=superuser
ENV         OS_PROJECT_NAME=admin
ENV         OS_USER_DOMAIN_NAME=Default
ENV         OS_PROJECT_DOMAIN_NAME=Default
ENV         OS_AUTH_URL=http://localhost:5000/v3
ENV         OS_SWIFT_URL=http://0.0.0.0:8080/v1
ENV         OS_IDENTITY_API_VERSION=3

# install system packages
ENV         PYTHONUNBUFFERED=1
ENV         DEBIAN_FRONTEND=noninteractive

ENV         VIRTUAL_ENV=/app/.venv
ENV         PATH=/app/.venv/bin:$PATH

RUN         rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN         --mount=type=cache,target=/var/cache/apt,sharing=private \
            --mount=type=cache,target=/var/lib/apt,sharing=private \
            apt-get update -q \
        &&  apt-get install -yq --no-install-recommends \
                xz-utils \
                liberasurecode1 \
                memcached \
                rsync \
                procps \
                psmisc \
                bash \
                curl \
        &&  apt-get autoremove -yq --purge

# Install s6
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/s6-overlay-noarch.tar.xz /tmp
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/s6-overlay-noarch.tar.xz.sha256 /tmp
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/s6-overlay-${S6_ARCH}.tar.xz /tmp/
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/s6-overlay-${S6_ARCH}.tar.xz.sha256 /tmp/
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/syslogd-overlay-noarch.tar.xz /tmp/
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/syslogd-overlay-noarch.tar.xz.sha256 /tmp/

RUN         cd /tmp \
        &&  sha256sum -c *.sha256 \
        &&  tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz \
        &&  tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
        &&  tar -C / -Jxpf /tmp/syslogd-overlay-noarch.tar.xz \
        &&  rm -rf /tmp/s6-overlay* \
        &&  rm -rf /tmp/syslogd*

# copy files
COPY        --chmod=755 docker/rootfs /

COPY        --from=builder /app/.venv /app/.venv

# Prepare
RUN         useradd -U swift \
        &&  useradd -U keystone \
        &&  useradd -U syslog \
        &&  useradd -U sysllog \
        &&  mkdir -p "/etc/swift" "/srv/node" "/srv/node/sdb1" "/var/cache/swift" "/var/run/swift" "/usr/local/src/" \
        &&  mkdir -p "/etc/keystone" "/var/lib/keystone" "/etc/keystone/fernet-keys/" \
# Build swift rings
        &&  swift-ring-builder /etc/swift/object.builder create 10 1 1 \
        &&  swift-ring-builder /etc/swift/object.builder add r1z1-127.0.0.1:6200/sdb1 1 \
        &&  swift-ring-builder /etc/swift/object.builder rebalance \
        &&  swift-ring-builder /etc/swift/container.builder create 10 1 1 \
        &&  swift-ring-builder /etc/swift/container.builder add r1z1-127.0.0.1:6201/sdb1 1 \
        &&  swift-ring-builder /etc/swift/container.builder rebalance \
        &&  swift-ring-builder /etc/swift/account.builder create 10 1 1 \
        &&  swift-ring-builder /etc/swift/account.builder add r1z1-127.0.0.1:6202/sdb1 1 \
        &&  swift-ring-builder /etc/swift/account.builder rebalance \
        &&  chown -R swift:swift "/etc/swift" "/srv/node" "/srv/node/sdb1" "/var/cache/swift" "/var/run/swift" "/usr/local/src/" \
# Setup Keystone
        &&  touch /var/lib/keystone/keystone.db \
# WAL mode: readers never block writers (unlike the default rollback-journal
# mode, where an idle-but-still-open reader connection blocks any writer's
# commit indefinitely). Must be set once, up front, before any table exists.
        &&  python3 -c "import sqlite3; sqlite3.connect('/var/lib/keystone/keystone.db').execute('PRAGMA journal_mode=WAL')" \
        &&  chown -R keystone:keystone "/etc/keystone" "/var/lib/keystone" "/etc/keystone/fernet-keys/" \
        &&  chmod -R 750  "/etc/keystone" "/var/lib/keystone" "/etc/keystone/fernet-keys/" \
        &&  su -s /bin/sh -c "keystone-manage db_sync" keystone \
        &&  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone \
        &&  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone \
        &&  keystone-manage bootstrap --bootstrap-password ${OS_PASSWORD} \
                --bootstrap-admin-url ${OS_AUTH_URL} \
                --bootstrap-internal-url ${OS_AUTH_URL} \
                --bootstrap-public-url ${OS_AUTH_URL} \
                --bootstrap-region-id RegionOne \
        &&  su -s /bin/sh -c "cd /etc/gunicorn && gunicorn & sleep 3" \
# Creating project and user
        &&  openstack user create --domain default --password veryfast swift \
        &&  openstack project create --domain default --description "Service test project" service \
        &&  openstack project create --domain default --description "Swift test project" swift-project \
        &&  openstack role add --project service --user swift admin \
        &&  openstack role add --project swift-project --user swift admin \
# Connect swift to keystone
        &&  openstack service create --name swift --description "OpenStack Object Storage" object-store \
        &&  openstack endpoint create --region RegionOne object-store internal $OS_SWIFT_URL/AUTH_%\(project_id\)s \
        &&  openstack endpoint create --region RegionOne object-store admin $OS_SWIFT_URL \
        &&  openstack endpoint create --region RegionOne object-store public $OS_SWIFT_URL/AUTH_%\(project_id\)s

COPY        scripts/generate_data.py /usr/local/bin/
RUN         chmod 755 /usr/local/bin/generate_data.py

ENTRYPOINT  ["/init"]
