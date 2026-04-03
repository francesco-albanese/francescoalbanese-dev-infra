SHELL := /bin/bash

.DEFAULT_GOAL := help

PROJECT_NAME ?= francescoalbanese-dev-infra
ACCOUNT ?= sandbox
AWS_PROFILE ?= sandbox-admin

include makefiles/terraform.mk

.PHONY: init plan apply destroy validate fmt