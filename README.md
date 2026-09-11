# Openstack swift and keystone container image

This container makes it easy to run *integration tests* against OpenStack Keystone and OpenStack Swift object storage.
It is not suitable for production.

The container starts both a swift and a keystone service so that integration tests can run against a single Docker container. The project's [Dockerfile](Dockerfile) is compatible with both amd64 and arm64 as BuildKit detects the target architecture automatically.

The following commands are available in the resulting container:
- openstack
- keystone
- swift
- bash

This image also comes with S3 API enabled. Swift and S3 have some compatibility issues, which are [described here](https://docs.openstack.org/swift/latest/s3_compat.html).

This project was created as a combination of other existing approaches, none of which served our needs:
- [Dockerfile from swift](https://github.com/openstack/swift)
- [dockerswiftaio/docker-swift](https://github.com/NVIDIA/docker-swift)
- [jeantil/openstack-swift-keystone-docker](https://github.com/jeantil/openstack-swift-keystone-docker)

## 🏃 Build and Run
<details><summary>Click to expand</summary>

### Prerequisites

- Docker
- [Vault CLI](https://developer.hashicorp.com/vault/install) if you are a member of SDD CSC

### Stack

This container is based on `python:3.14.7-slim-trixie` and installs Keystone, Swift, and their
clients straight from PyPI via [uv](https://docs.astral.sh/uv/) (see `pyproject.toml` for the
direct dependencies and `uv.lock` for the exact resolved pins). Furthermore, the image includes
[s6-overlay](https://github.com/just-containers/s6-overlay) to manage processes.

### How to use this container

The main users of this repository are assumed to be the group members of SDD CSC. If you do not belong to this group, go to [Using public sources](#using-public-sources).

The [Dockerfile](Dockerfile) uses Artifactory as the source for both Docker images and Python dependencies. Therefore, before you can build the Docker image, you must first log in to Vault and two Artifactory Docker registries. The easiest way to authenticate against these is to use the accompanying [Makefile](Makefile). By running

```sh
make all
```

you will be first asked to log in to Vault to get the necessary secrets, and then asked to log in to the Docker registries in Artifactory. Use the external password for Vault and the internal password for Artifactory. After fetching secrets and logging in to Artifactory, the Makefile target `all` builds a `keystone-swift` Docker image and runs it in the background.

To run any of these steps individually, the Makefile offers targets `setup`, `build`, and `run`. To stop the image, run

```sh
make stop
```

#### Using public sources

If you do not have access to SDD Vault, you can instead run Makefile target

```sh
make all_public
```

This target first regenerates the [uv.lock](uv.lock) file, since the file contains links to CSC Artifactory, and then builds the Docker container and runs it in the background.

To see all available targets, run `make help`.

### Logging

Service logs are sent to stdout by default. To silence them, pass `S6_LOGGING=1` when running
the container, e.g.

    docker run -d -p 5000:5000 -p 8080:8080 --env S6_LOGGING=1 --name keystone-swift keystone-swift

Note that `make run` does not forward this variable, so use `docker run` directly if you need to
change it.

</details>

## 📚 Usage
<details><summary>Click to expand</summary>

Use the scripts to generate data into the object storage, and test the endpoints.

### Preconfigured credentials
The container comes with 2 preconfigured accounts:
- admin / superuser
- swift / veryfast

### Preconfigured projects
The container comes with 2 preconfigured projects:
- service (Service test project) | swift admin user
- swift-project (Swift test project) | swift admin user

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

### Sample httpie commands

Keystone Identity v3

    echo '{"auth":{"identity":{"methods":["password"],"password":{"user":{"name":"swift","domain":{"name":"Default"},"password":"veryfast"}}},"scope":{"project":{"domain":{"id":"default"},"name":"test"}}}}' | http POST :5000/v3/auth/tokens

TempAuth

    http http://127.0.0.1:8080/auth/v1.0 X-Storage-User:test:tester X-Storage-Pass:testing

### Sample curl commands

Keystone Identity v3

    curl -X POST -H 'Content-Type: application/json' -d '{"auth":{"identity":{"methods":["password"],"password":{"user":{"name":"swift","domain":{"name":"Default"},"password":"veryfast"}}},"scope":{"project":{"domain":{"id":"default"},"name":"test"}}}}' http://127.0.0.1:5000/v3/auth/tokens

TempAuth

    curl -H 'X-Storage-User: test:tester' -H 'X-Storage-Pass: testing' http://127.0.0.1:8080/auth/v1.0

### S3 API

To use S3, generate credentials and use them to authenticate against the S3 API.
Below is an example using the credentials with [`s3cmd`](https://github.com/s3tools/s3cmd).

1. Create credentials
```bash
$ docker exec -it <image-id> bash
$ openstack ec2 credentials create
+------------+---------------------------------------------------------------------------------------------------------------------------------+
| Field      | Value                                                                                                                           |
+------------+---------------------------------------------------------------------------------------------------------------------------------+
| access     | 0a09f306baa04358aa88e50c4853329f                                                                                                |
| links      | {'self': 'http://localhost:5000/v3/users/2855fdd6794e4d38b4e14b036094524f/credentials/OS-EC2/0a09f306baa04358aa88e50c4853329f'} |
| project_id | 3ec1214fab494db0b8e2fb4e8f16b42a                                                                                                |
| secret     | b15fdf7a8ed947f7afe6fa3b01a376cc                                                                                                |
| trust_id   | None                                                                                                                            |
| user_id    | 2855fdd6794e4d38b4e14b036094524f                                                                                                |
+------------+---------------------------------------------------------------------------------------------------------------------------------+

```
2. Create s3 config file
```bash
cat > s3.cfg << EOF
[default]
access_key = 0a09f306baa04358aa88e50c4853329f
secret_key = b15fdf7a8ed947f7afe6fa3b01a376cc
host_base = 127.0.0.1:8080
host_bucket = 127.0.0.1:8080
use_https = false

EOF
```
3. Use s3cmd
```bash
# create a bucket
$ s3cmd -c s3.cfg mb s3://config
Bucket 's3://config/' created

# upload the config file
$ s3cmd -c s3.cfg put s3.cfg s3://config/s3.cfg
upload: 's3.cfg' -> 's3://config/s3.cfg'  [1 of 1]
 176 of 176   100% in    0s     3.33 KB/s  done

# list all objects
$ s3cmd -c s3.cfg la
2023-12-11 18:23          176  s3://config/s3.cfg
```

### Pouta Access Token
A Python script has been added to mock the feature in Pouta in which a token from SDS AAI's userinfo can be exchanged for an unscoped token that works with OpenStack Keystone. The Python server is running in port 5001 and also proxies all other requests to port 5000, meaning all Keystone endpoints work in port 5001 as well.

</details>

## 📜 License

<details><summary>Click to expand</summary>

`docker-keystone-swift` and all its sources are released under `MIT`, see [LICENSE](LICENSE).

</details>
