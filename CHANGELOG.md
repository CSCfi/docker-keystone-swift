# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Calendar Versioning](https://calver.org/).

## [Unreleased]

### Fixed

- push release to `ghcr.io` with a command that does not strip the image of its multi-platform support
- in `2-upload-ghcr-image` CI job, define `DOCKER_CONFIG` only after the image has been pulled from the registry

## [2026.9.0] - 2026-09-17

### Changed

- (users) logs are directed to stdout by default
- (users) install Docker and Python dependencies via Artifactory. Access to Artifactory is gained by running `Makefile` target `setup`, which populates `.env` with secrets from Vault
- (users) image supports multiple platforms without the `ARCHITECTURE` argument in `Dockerfile`
- use `Faker` instead of `lorem` for generating random text
- update to use Python 3.14 and trixie. Install dependencies with `uv`

### Fixed

- (users) removed `--init` flag from README instructions
- set maximum password length in `keystone.conf` to 72 to silence warnings
- Added authentication to `keystonemiddleware`'s `s3token`
- run sqlite in WAL mode to prevent database from locking
- replace deleted `keystone-wsgi-public` with `gunicorn`

### Added

- (users) `Makefile` with targets to help build and run the code. There are also targets that users outside SDD CSC can utilize which do not use Artifactory or Vault.
- (users) release image in Artifactory
- Gitlab CI pipeline


[Unreleased]: https://gitlab.ci.csc.fi/sds-dev/sd-tools/docker-keystone-swift/compare/2026.9.0...HEAD
[2026.9.0]: https://gitlab.ci.csc.fi/sds-dev/sd-tools/docker-keystone-swift/-/releases/2026.9.0
