#####################################################
#                                                   #
#  OpenStack Keystone and Swift-All-In-One Wallaby  #
#                                                   #
#####################################################

# https://releases.openstack.org/wallaby/index.html

FROM        python:3.9-slim as builder

ENV         ARCH amd64
ENV         SWIFT_VERSION 2.27.0
ENV         KEYSTONE_VERSION 19.0.1
ENV         KEYSTONEMIDDLEWARE_VERSION 9.2.0
ENV         SWIFTCLIENT_VERSION 3.11.1
ENV         KEYSTONECLIENT_VERSION 4.2.0
ENV         OPENSTACKCLIENT_VERSION 5.5.1

ENV         DEBIAN_FRONTEND=noninteractive

ADD         https://tarballs.openstack.org/swift/swift-$SWIFT_VERSION.tar.gz /tmp/
ADD         https://tarballs.openstack.org/keystone/keystone-$KEYSTONE_VERSION.tar.gz /tmp/
ADD         https://tarballs.openstack.org/keystonemiddleware/keystonemiddleware-$KEYSTONEMIDDLEWARE_VERSION.tar.gz /tmp/

ADD         https://tarballs.openstack.org/python-swiftclient/python-swiftclient-$SWIFTCLIENT_VERSION.tar.gz /tmp/
ADD         https://tarballs.openstack.org/python-keystoneclient/python-keystoneclient-$KEYSTONECLIENT_VERSION.tar.gz /tmp/
ADD         https://tarballs.openstack.org/python-openstackclient/python-openstackclient-$OPENSTACKCLIENT_VERSION.tar.gz /tmp/

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

# Install Keystone + swift + clients
COPY        requirements.txt /usr/local/src/

RUN         --mount=type=cache,target=/root/.cache/pip \
            tar -C /usr/local/src/ -xf /tmp/swift-${SWIFT_VERSION}.tar.gz \
        &&  tar -C /usr/local/src/ -xf /tmp/keystone-${KEYSTONE_VERSION}.tar.gz \
        &&  tar -C /usr/local/src/ -xf /tmp/keystonemiddleware-${KEYSTONEMIDDLEWARE_VERSION}.tar.gz \
        &&  tar -C /usr/local/src/ -xf /tmp/python-swiftclient-${SWIFTCLIENT_VERSION}.tar.gz \
        &&  tar -C /usr/local/src/ -xf /tmp/python-keystoneclient-${KEYSTONECLIENT_VERSION}.tar.gz \
        &&  tar -C /usr/local/src/ -xf /tmp/python-openstackclient-${OPENSTACKCLIENT_VERSION}.tar.gz \
        &&  pip install -U pip \
        &&  pip install -r /usr/local/src/requirements.txt \
        &&  pip install /usr/local/src/swift-${SWIFT_VERSION}/ \
        &&  pip install /usr/local/src/keystone-${KEYSTONE_VERSION}/ \
        &&  pip install /usr/local/src/keystonemiddleware-${KEYSTONEMIDDLEWARE_VERSION}/ \
        &&  pip install /usr/local/src/python-swiftclient-${SWIFTCLIENT_VERSION}/ \
        &&  pip install /usr/local/src/python-keystoneclient-${KEYSTONECLIENT_VERSION}/ \
        &&  pip install /usr/local/src/python-openstackclient-${OPENSTACKCLIENT_VERSION}/


FROM        python:3.9-slim

ENV         ARCH amd64
ENV         S6_LOGGING 1
ENV         S6_VERSION 2.2.0.3
ENV         SOCKLOG_VERSION 3.1.2-0

ENV         OS_USERNAME=admin
ENV         OS_PASSWORD=superuser
ENV         OS_PROJECT_NAME=admin
ENV         OS_USER_DOMAIN_NAME=Default
ENV         OS_PROJECT_DOMAIN_NAME=Default
ENV         OS_AUTH_URL=http://localhost:5000/v3
ENV         OS_SWIFT_URL=http://localhost:8080/v1
ENV         OS_IDENTITY_API_VERSION=3

ENV         DEBIAN_FRONTEND=noninteractive

ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/s6-overlay-$ARCH.tar.gz /tmp/
ADD         https://github.com/just-containers/s6-overlay/releases/download/v$S6_VERSION/s6-overlay-$ARCH.tar.gz.sig /tmp/
ADD         https://github.com/just-containers/socklog-overlay/releases/download/v$SOCKLOG_VERSION/socklog-overlay-$ARCH.tar.gz /tmp/


# Install s6
RUN         tar -C / -xf /tmp/s6-overlay-$ARCH.tar.gz \
        &&  tar -C / -xf /tmp/socklog-overlay-$ARCH.tar.gz \
        &&  rm -rf /tmp/s6-overlay* \
        &&  rm -rf /tmp/socklog-overlay*

RUN         rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN         --mount=type=cache,target=/var/cache/apt,sharing=private \
            --mount=type=cache,target=/var/lib/apt,sharing=private \
            apt-get update -q \
        &&  apt-get install -yq --no-install-recommends \
                liberasurecode1 \
                memcached \
                rsyslog \
                rsync \
                procps \
                psmisc \
                bash \
        &&  apt-get autoremove -yq --purge

COPY        docker/rootfs /
COPY        scripts/generate_data.py /usr/local/bin/

COPY        --from=builder /usr/local/bin /usr/local/bin
COPY        --from=builder /usr/local/etc /usr/local/etc
COPY        --from=builder /usr/local/include /usr/local/include
COPY        --from=builder /usr/local/lib /usr/local/lib

# Prepare
RUN         useradd -U swift \ 
        &&  useradd -U keystone \ 
        &&  mkdir -p "/etc/swift" "/srv/node" "/srv/node/sdb1" "/var/cache/swift" "/var/log/socklog/swift" "/var/log/swift/" "/var/run/swift" "/usr/local/src/" \
        &&  mkdir -p "/etc/keystone" "/var/log/keystone" "/var/lib/keystone" "/etc/keystone/fernet-keys/" \
        &&  chmod 755 /usr/local/bin/generate_data.py \
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
        &&  chown -R swift:swift "/etc/swift" "/srv/node" "/srv/node/sdb1" "/var/cache/swift" "/var/log/socklog/swift" "/var/log/swift/" "/var/run/swift" "/usr/local/src/" \
# Setup Keystone
        &&  touch /var/lib/keystone/keystone.db \
        &&  chown -R keystone:keystone  "/etc/keystone" "/var/log/keystone" "/var/lib/keystone" "/etc/keystone/fernet-keys/" \
        &&  su -s /bin/sh -c "keystone-manage db_sync" keystone \
        &&  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone \
        &&  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone \
        &&  keystone-manage bootstrap --bootstrap-password ${OS_PASSWORD} \
                --bootstrap-admin-url ${OS_AUTH_URL} \
                --bootstrap-internal-url ${OS_AUTH_URL} \
                --bootstrap-public-url ${OS_AUTH_URL} \
                --bootstrap-region-id RegionOne \
        &&  su -s /bin/sh -c "/usr/local/bin/keystone-wsgi-public -b localhost -p 5000 & sleep 3" \
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


ENTRYPOINT  ["/init"]
