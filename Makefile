SHELL := /bin/bash

.DEFAULT_GOAL := help

PROJECT_NAME ?= francescoalbanese-dev-infra
ACCOUNT ?= sandbox
AWS_PROFILE ?= sandbox-admin

include makefiles/terraform.mk

.PHONY: init plan apply destroy validate fmt dashboard dev-setup

dev-setup: ## Install prek and wire up git hooks
	uv tool install prek
	prek install

DASHBOARD_FUNCTION ?= francescoalbanese-dev-dashboard-generator

dashboard: ## Invoke dashboard Lambda and open the presigned URL in a browser
	@tmp=$$(mktemp); \
	aws lambda invoke \
		$(if $(AWS_PROFILE),--profile $(AWS_PROFILE),) \
		--function-name $(DASHBOARD_FUNCTION) \
		--payload '{}' \
		--cli-binary-format raw-in-base64-out \
		"$$tmp" >/dev/null; \
	url=$$(jq -r '.headers.Location' "$$tmp"); \
	rm -f "$$tmp"; \
	echo "Opening $$url"; \
	open "$$url"