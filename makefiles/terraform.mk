SHELL := /bin/bash

terraform = AWS_PROFILE=$(AWS_PROFILE) terraform
STACKS = $(dir $(wildcard terraform/*/.))
STACKS := $(sort $(notdir $(STACKS:/=)))

all:

.SECONDEXPANSION:
$(STACKS): $$@-init $$@-validate $$@-plan $$@-apply $$@-destroy

STATE_CONF := state.conf
environmental_KEY := $(PROJECT_NAME)
environmental_FLAGS :=

tf-setup: ## install tfenv and tflint (macOS: use brew install terraform instead)
tf-setup:
	@echo "Installing Terraform tooling..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		echo "macOS detected. Recommended: 'brew install terraform tfenv tflint'"; \
		echo "Attempting tfenv installation for manual PATH setup..."; \
		if [ ! -d "$$HOME/.tfenv" ]; then \
			git clone https://github.com/tfutils/tfenv.git $$HOME/.tfenv; \
			echo "Add to your shell rc: export PATH=\"\$$HOME/.tfenv/bin:\$$PATH\""; \
		fi; \
	else \
		if [ ! -d "$$HOME/.tfenv" ]; then \
			git clone https://github.com/tfutils/tfenv.git $$HOME/.tfenv && \
			echo 'export PATH="$$HOME/.tfenv/bin:$$PATH"' >> $$HOME/.bashrc; \
		fi; \
		if ! type tflint >/dev/null 2>&1; then \
			curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash; \
		fi; \
	fi

tf-configure: ## swap terraform to correct version using tfenv (optional)
tf-configure:
	@if command -v tfenv >/dev/null 2>&1; then \
		TF_VERSION=$$(grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' $(PWD)/terraform/environmental/terraform.tf | head -n1); \
		if [ -n "$$TF_VERSION" ]; then \
			echo "Setting Terraform version to $$TF_VERSION via tfenv..."; \
			tfenv install $$TF_VERSION 2>/dev/null || true; \
			tfenv use $$TF_VERSION; \
		else \
			echo "Warning: Could not extract Terraform version from terraform.tf"; \
		fi; \
	elif command -v terraform >/dev/null 2>&1; then \
		echo "tfenv not installed, using system terraform:"; \
		terraform version; \
	else \
		echo "Neither tfenv nor terraform found. Run 'make tf-setup' or install terraform."; \
		exit 1; \
	fi

clean: ## reset all terraform stacks
clean: $(addsuffix -clean, $(STACKS))

lint: ## run tflint on all terraform stacks
lint: $(addsuffix -lint, $(STACKS))

init: ## initialize all terraform stacks
init: $(addsuffix -init, $(STACKS))

init-no-backend: ## initialize all terraform stacks with -backend=false
init-no-backend: $(addsuffix -init-no-backend, $(STACKS))

upgrade: ## upgrade all terraform stacks
upgrade: TF_FLAGS ?= -upgrade
upgrade: $(addsuffix -init, $(STACKS))


validate: ## validate all terraform stacks
validate: $(addsuffix -validate, $(STACKS))

plan: ## show plan for all terraform stacks
plan: $(addsuffix -plan, $(STACKS))

apply: ## apply all terraform stacks
apply: 
	@echo "++++ Applying environmental stack ++++"
	$(terraform) -chdir=terraform/environmental apply $(environmental_FLAGS) $(TF_FLAGS)

destroy: ## destroy all terraform stacks
destroy: $(addsuffix -destroy, $(STACKS))

# Pattern rules for stack-specific operations
%-clean:
	@echo "++++ Cleaning $* stack ++++"
	@rm -rf terraform/$*/.terraform terraform/$*/.terraform.lock.hcl

%-lint:
	@echo "++++ Linting $* stack ++++"
	@cd terraform/$* && tflint

%-init:
	@echo "++++ Initializing $* stack ++++"
	@if [ -f $(STATE_CONF) ]; then \
		$(terraform) -chdir=terraform/$* init -backend-config=../../$(STATE_CONF) $($*_FLAGS) $(TF_FLAGS); \
	else \
		$(terraform) -chdir=terraform/$* init $($*_FLAGS) $(TF_FLAGS); \
	fi

%-init-no-backend:
	@echo "++++ Initializing $* stack (no backend) ++++"
	@$(terraform) -chdir=terraform/$* init -backend=false $($*_FLAGS) $(TF_FLAGS)

%-validate:
	@echo "++++ Validating $* stack ++++"
	@$(terraform) -chdir=terraform/$* validate

%-plan:
	@echo "++++ Planning $* stack ++++"
	@$(terraform) -chdir=terraform/$* plan $($*_FLAGS) $(TF_FLAGS)

%-apply:
	@echo "++++ Applying $* stack ++++"
	@$(terraform) -chdir=terraform/$* apply $($*_FLAGS) $(TF_FLAGS)

%-destroy:
	@echo "++++ Destroying $* stack ++++"
	@$(terraform) -chdir=terraform/$* destroy $($*_FLAGS) $(TF_FLAGS)

.PHONY: fmt
fmt: ## format all terraform
	@$(terraform) fmt -recursive terraform/

help: ## show this help message
	@echo "=========================================="
	@echo "  AWS Multi-Account Terraform Makefile"
	@echo "=========================================="
	@echo ""
	@echo "DETECTED STACKS:"
	@echo "  $(STACKS)"
	@echo ""
	@echo "GLOBAL TARGETS:"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | uniq | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "STACK-SPECIFIC TARGETS:"
	@echo "  Pattern: make <stack>-<action>"
	@echo ""
	@echo "  Available actions:"
	@echo -e "    \033[33minit\033[0m         - Initialize terraform (with state.conf if exists)"
	@echo -e "    \033[33mvalidate\033[0m     - Validate terraform configuration"
	@echo -e "    \033[33mplan\033[0m         - Show execution plan"
	@echo -e "    \033[33mapply\033[0m        - Apply changes"
	@echo -e "    \033[33mdestroy\033[0m      - Destroy resources"
	@echo -e "    \033[33mclean\033[0m        - Remove .terraform/ and lock file"
	@echo -e "    \033[33mlint\033[0m         - Run tflint"
	@echo ""
	@echo "  Examples:"
	@for stack in $(STACKS); do \
		echo -e "    \033[36mmake $$stack-init\033[0m"; \
		echo -e "    \033[36mmake $$stack-plan\033[0m"; \
		echo -e "    \033[36mmake $$stack-apply\033[0m"; \
		echo ""; \
	done
	@echo "VARIABLES:"
	@echo "  ACCOUNT=<name>        Target account (default: sandbox)"
	@echo "  AWS_PROFILE=<profile> AWS profile to use (default: sandbox)"
	@echo "  TF_FLAGS=<flags>      Additional terraform flags"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make environmental-plan ACCOUNT=staging AWS_PROFILE=staging"
	@echo "  make init                    # Init all stacks"
	@echo "  make clean                   # Clean all stacks"