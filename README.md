# Openstack swift and keystone container image

This container makes it easy to run *integration tests* against OpenStack Keystone and OpenStack Swift object storage.
It is not suitable for production. 

The container starts both a swift and a keystone service so that integration
tests can run against a single Docker container.

This image was created as a combination of other existing approaches, none of which served our needs:
- [Dockerfile from swift](https://github.com/openstack/swift)
- [dockerswiftaio/docker-swift](https://github.com/NVIDIA/docker-swift)
- [jeantil/openstack-swift-keystone-docker](https://github.com/jeantil/openstack-swift-keystone-docker)

## Stack
This container is based on `python:3.8-slim` and installs tarballs from
[OpenStack release Wallaby](https://docs.openstack.org/wallaby/install/).
Furthermore, the image includes [s6-overlay](https://github.com/just-containers/s6-overlay)
to manage processes.

## How to use this container
Build the image with

    docker buildx build -t keystone-swift .

Start the container using the following command:

    docker run -d -p 5000:5000 -p 8080:8080 --name keystone-swift keystone-swift

Or use the built images from ghrc.io

    docker run -d -p 5000:5000 -p 8080:8080 --name keystone-swift ghcr.io/cscfi/keystone-swift

Stop it with

    docker stop keystone-swift

By default, the image outputs no logs, but you can pass `S6_LOGGING=0` when running the image so that it sends logs to stdout

    docker run -d -p 5000:5000 -p 8080:8080 --env S6_LOGGING=0 --name keystone-swift keystone-swift


The following commands are available in the container:
- openstack
- keystone
- swift
- bash

## Extras
Use the scripts to generate data into the object storage, and test the endpoints.

## Preconfigured credentials
The container comes with 2 preconfigures accounts:
- admin / superuser
- swift / veryfast

### Keystone Identity v3 accounts 
Default endpoint http://127.0.0.1:5000/v3

#### Administrative account

    export OS_USERNAME=admin
    export OS_PASSWORD=superuser
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://127.0.0.1:5000/v3
    export OS_IDENTITY_API_VERSION=3

#### swift service account

    export OS_USERNAME=swift
    export OS_PASSWORD=veryfast
    export OS_PROJECT_NAME=service
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://127.0.0.1:5000/v3
    export OS_IDENTITY_API_VERSION=3

### Swift tempAuth accounts

Default endpoint http://127.0.0.1:8080/auth/v1.0

#### Admin account

    USERNAME=admin
    PASSWORD=admin
    TENANT_NAME=admin

#### tester account

    USERNAME=tester
    PASSWORD=testing
    TENANT_NAME=test


## Sample httpie commands

Keystone Identity v3

    echo '{"auth":{"identity":{"methods":["password"],"password":{"user":{"name":"swift","domain":{"name":"Default"},"password":"veryfast"}}},"scope":{"project":{"domain":{"id":"default"},"name":"test"}}}}' | http POST :5000/v3/auth/tokens

TempAuth

    http http://127.0.0.1:8080/auth/v1.0 X-Storage-User:test:tester X-Storage-Pass:testing 

## Sample curl commands

Keystone Identity v3

    curl -X POST -H 'Content-Type: application/json' -d '{"auth":{"identity":{"methods":["password"],"password":{"user":{"name":"swift","domain":{"name":"Default"},"password":"veryfast"}}},"scope":{"project":{"domain":{"id":"default"},"name":"test"}}}}' http://127.0.0.1:5000/v3/auth/tokens

TempAuth

    curl -H 'X-Storage-User: test:tester' -H 'X-Storage-Pass: testing' http://127.0.0.1:8080/auth/v1.0

# License

`docker-keystone-swift` and all it sources are released under MIT License.
