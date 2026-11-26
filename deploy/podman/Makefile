# SPDX-License-Identifier: BSD-2-Clause
.PHONY: help config up down logs ps verify clean python-build python-test python-scan scan-all
COMPOSE ?= podman compose
ENV_FILE ?= .env
IMAGE ?= localhost/shirudo-python-demo:local

help:
	@printf '%s\n' 'config up down logs ps verify clean python-build python-test python-scan scan-all'
config:
	$(COMPOSE) --env-file $(ENV_FILE) config
up:
	$(COMPOSE) --env-file $(ENV_FILE) up -d
down:
	$(COMPOSE) --env-file $(ENV_FILE) down
logs:
	$(COMPOSE) --env-file $(ENV_FILE) logs -f
ps:
	$(COMPOSE) --env-file $(ENV_FILE) ps
verify:
	curl --fail --cacert secrets/registry/server.crt https://127.0.0.1:15444/v2/
	curl --fail http://127.0.0.1:18124/ping
clean:
	$(COMPOSE) --env-file $(ENV_FILE) down -v
python-build:
	podman build -f python-app/Containerfile -t $(IMAGE) python-app
python-test: python-build
	IMAGE=$(IMAGE) scripts/test-python-container.sh
python-scan: python-build
	IMAGE=$(IMAGE) scripts/python-security-check.sh
scan-all:
	scripts/scan-all-workloads.sh
