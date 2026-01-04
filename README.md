# francescoalbanese-dev-infra

Terraform infrastructure for `francescoalbanese.dev` domain.

## Purpose

Centralized Route53 hosted zone in AWS shared-services account, enabling:
- DNS management for personal domain
- Cross-project reuse (mTLS API Gateway, personal website, etc.)
- Easy teardown when no longer needed

## Architecture

- **Account**: shared-services (088994864650)
- **Region**: eu-west-2
- **State**: S3 backend in shared-services
- **Resource**: Route53 public hosted zone

## Usage

```bash
# Initialize
make environmental-init

# Plan
make environmental-plan

# Apply
make environmental-apply

# Get nameservers
terraform -chdir=terraform/environmental output nameservers
```

## DNS

Domain purchased from Porkbun, NS records pointed to AWS Route53.

## Destroy

```bash
make environmental-destroy
```
