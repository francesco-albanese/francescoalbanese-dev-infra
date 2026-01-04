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

# Get nameservers for Porkbun
terraform -chdir=terraform/environmental output nameservers
```

## Post-Apply

Copy the 4 nameservers to Porkbun:
1. Login to Porkbun → Domain → francescoalbanese.dev
2. DNS → Authoritative Nameservers
3. Replace default NS with Route53 NS

## Destroy

```bash
make environmental-destroy
```
