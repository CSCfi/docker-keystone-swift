SHELL := /bin/bash
MAKEFLAGS += --no-print-directory --always-make

-include .env
export

define write_secret
printf "%s=" $(1) >> .env; \
vault kv get --field=$(3) secret/$(2) >> .env; \
echo >> .env;
endef

# Default target
# Print list of available targets. Only rows in the format `target: ## description` are printed
help:
	@echo "Available targets:"
	@awk '/^[a-zA-Z0-9_-]+:.*?## / {printf "  %-20s %s\n", $$1, substr($$0, index($$0, "##") + 3)}' $(MAKEFILE_LIST)

all: setup build run ## Fetch secrets from Vault, and build and run image

build: ## Build Docker image
	@docker buildx build \
	--build-arg ARTIFACTORY_SERVER=$(ARTIFACTORY_SERVER)/ \
	--build-arg ARTIFACTORY_SERVER_GHCR=$(ARTIFACTORY_SERVER_GHCR)/ \
	--build-arg UV_DEFAULT_INDEX="artifactory=$(ARTIFACTORY_PYPI_REGISTRY)/simple" \
	--build-arg UV_INDEX_ARTIFACTORY_USERNAME=$(ARTIFACTORY_READ_ONLY_USER) \
	--secret id=artifactory_token,env=ARTIFACTORY_PYPI_TOKEN \
	-t keystone-swift .

run: stop ## Run Docker image
	@docker run -d -p 5000:5000 -p 8080:8080 --name keystone-swift keystone-swift

setup: get_env ## Get secrets from Vault and login to Artifactory registries
	docker login $(ARTIFACTORY_SERVER)
	docker login $(ARTIFACTORY_SERVER_GHCR)

stop: ## Stop and remove Docker image
	@docker stop keystone-swift 2> /dev/null || true
	@docker rm -f keystone-swift 2> /dev/null || true

get_env: ## Get secrets from Vault for building image
	@vault -v > /dev/null 2>&1 || { echo "⚠️  \033[31;1mVault CLI is not installed\033[0m ⚠️"; exit 1; }
	@rm -f .env
	@export VAULT_TOKEN=$$(vault login -method=oidc -token-only); \
	$(call write_secret,ARTIFACTORY_SERVER,internal-urls,artifactory-docker) \
	$(call write_secret,ARTIFACTORY_SERVER_GHCR,internal-urls,artifactory-ghcr) \
	$(call write_secret,ARTIFACTORY_READ_ONLY_USER,robots/artifactory-read-only,username) \
	$(call write_secret,ARTIFACTORY_PYPI_REGISTRY,artifactory,pypi-registry) \
	$(call write_secret,ARTIFACTORY_PYPI_TOKEN,artifactory,pypi-token)
	@echo "Secrets written successfully"
