# vprofile-infra

Minimal Terraform configuration for a public-subnet Amazon EKS cluster in `us-east-1`.

## Overview

This project provisions:
- A VPC with a public subnet in two availability zones
- An internet gateway and public route table
- An EKS control plane and managed node group
- IAM roles for cluster and worker nodes
- EKS OIDC provider and EBS CSI driver IRSA integration

## Prerequisites

- Terraform 1.3 or newer
- AWS CLI configured with appropriate credentials
- An S3 bucket for the Terraform backend state

## Files

- `main.tf` - main infrastructure resources
- `variables.tf` - configurable values
- `outputs.tf` - output values
- `backend.tf` - S3 backend configuration
- `.gitignore` - ignores Terraform local state and cache files

## Usage

1. Update the backend bucket name in `backend.tf` if needed.
2. Initialize Terraform:
   ```bash
   terraform init
   ```
3. Review the execution plan:
   ```bash
   terraform plan
   ```
4. Apply the configuration:
   ```bash
   terraform apply
   ```

## Notes

- The cluster uses only public subnets and no NAT gateway for a minimal-cost design.
- The AWS EBS CSI Driver is configured with IRSA and does not create a separate Kubernetes service account manually.
