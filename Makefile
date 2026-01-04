SHELL := /bin/bash

.DEFAULT_GOAL := help

PROJECT_NAME ?= francescoalbanese-dev-infra
AWS_PROFILE ?= shared-services-admin
terraform = AWS_PROFILE=$(AWS_PROFILE) terraform

include makefiles/terraform.mk

.PHONY: init plan apply destroy validate fmt