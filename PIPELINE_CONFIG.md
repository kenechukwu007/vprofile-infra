# Pipeline Configuration Guide

This file contains templates and configuration examples for the Terraform GitOps pipeline.

## GitHub Secrets Template

Copy and update these values in GitHub Settings → Secrets and variables → Actions:

```
# AWS OIDC Role ARN
AWS_ROLE_TO_ASSUME=arn:aws:iam::YOUR_ACCOUNT_ID:role/github-oidc-role

# Terraform Backend Configuration
TF_BACKEND_BUCKET=your-terraform-state-bucket
TF_BACKEND_KEY=vprofile-infra/terraform.tfstate
TF_BACKEND_DYNAMODB=terraform-locks
AWS_REGION=us-east-1

# EKS Configuration
EKS_CLUSTER_NAME=vprofile-eks-cluster

# Notifications (Optional)
SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## AWS IAM Trust Policy

Replace values and create this IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/vprofile-infra:*"
        }
      }
    }
  ]
}
```

## AWS IAM Policy for Terraform

Attach this policy to the github-oidc-role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-terraform-state-bucket",
        "arn:aws:s3:::your-terraform-state-bucket/*"
      ]
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:*:YOUR_ACCOUNT_ID:table/terraform-locks"
    },
    {
      "Sid": "EKSManagement",
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPCManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecurityGroupManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2AddonManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    }
  ]
}
```

## Environment Protection Configuration

Set up manual approval for production deployments:

1. Go to: Repository Settings → Environments → Create "production"
2. Add these settings:

   **Deployment branches**: 
   - Restrict to main branch only

   **Required reviewers**:
   - ☑ Require reviewers
   - Add team members: @product-team, @infrastructure-team

   **Protection rules**:
   - ☑ Prevent self-review
   - ☑ Deploy from protected branches

## GitHub Branch Protection Rules

Configure on main branch:

```
Settings → Branches → Add rule

Branch name pattern: main

Protect matching branches:
☑ Require a pull request before merging
  ☑ Require approvals (2)
  ☑ Require conversation resolution
  ☑ Require status checks to pass
    ✓ terraform-validate-plan / terraform-validate-plan
    ✓ terraform-validate-plan / eks-validation

☑ Require branches to be up to date
☑ Require status checks to pass before merging
☑ Require code reviews before merging (2 approvals)
☑ Require review from Code Owners
☑ Allow auto-merge
☑ Dismiss stale PR approvals when new commits push
☑ Require signed commits
```

## Slack Integration

To add Slack notifications:

1. Create Slack Webhook:
   - Go to Slack Workspace Settings → Apps & Integrations
   - Search "Incoming Webhooks"
   - Create New Webhook
   - Copy webhook URL

2. Add to GitHub Secrets:
   - Name: `SLACK_WEBHOOK`
   - Value: `https://hooks.slack.com/services/YOUR/WEBHOOK/URL`

3. Test notification:
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test from GitHub Actions"}' \
     YOUR_WEBHOOK_URL
   ```

## Custom Workflow Configuration

### Adjust Drift Detection Schedule

Edit `.github/workflows/terraform-drift-detection.yaml`:

```yaml
on:
  schedule:
    # Change cron expression (UTC)
    # Format: minute hour day month weekday
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
    - cron: '0 */6 * * *' # Every 6 hours
    - cron: '0 8-17 * * 1-5' # Weekdays 8 AM - 5 PM UTC
```

### Adjust EKS Validation Schedule

Edit `.github/workflows/eks-validation.yaml`:

```yaml
on:
  schedule:
    # Every 6 hours
    - cron: '0 */6 * * *'
    # Or daily at 3 AM UTC
    - cron: '0 3 * * *'
```

### Add Additional Validators

Add custom steps in any workflow:

```yaml
- name: Custom Validation
  run: |
    echo "Running custom checks..."
    # Add your validation logic
    
- name: Security Scan
  run: |
    # Example: Run checkov on Terraform
    pip install checkov
    checkov -d .
```

## Common Configuration Updates

### Change AWS Region

Update in GitHub Secrets or in terraform files:

```bash
# Add to GitHub Secrets or .github/workflows/
AWS_REGION=us-west-2
```

### Change Cluster Name

```bash
# Option 1: Update GitHub Secret
EKS_CLUSTER_NAME=my-custom-cluster-name

# Option 2: Update Terraform default
# In variables.tf:
default = "my-custom-cluster-name"
```

### Change State Backend

```bash
# Update GitHub Secrets
TF_BACKEND_BUCKET=my-new-bucket
TF_BACKEND_KEY=path/to/state.tfstate
TF_BACKEND_DYNAMODB=my-lock-table
```

## Troubleshooting Configuration

### Verify OIDC Setup

```bash
# Check OIDC provider exists
aws iam list-open-id-connect-providers

# Get provider details
aws iam get-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com

# Test role assumption (from GitHub Actions)
# The workflow logs will show if OIDC token validation fails
```

### Debug Workflow Issues

1. Check workflow logs in GitHub Actions
2. Enable debug mode: Add `ACTIONS_STEP_DEBUG=true` secret
3. Review recent runs and error messages

### Test Local Terraform

```bash
# Initialize with backend config
terraform init \
  -backend-config="bucket=your-bucket" \
  -backend-config="key=vprofile-infra/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-locks"

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

## Files in This Pipeline

- `.github/workflows/terraform-pr.yaml` - PR validation
- `.github/workflows/terraform-apply.yaml` - Manual apply with approval
- `.github/workflows/terraform-drift-detection.yaml` - Daily drift detection
- `.github/workflows/eks-validation.yaml` - EKS cluster validation
- `PIPELINE_SETUP.md` - Complete setup guide
- `PIPELINE_CONFIG.md` - This file

---

**Last Updated**: 2024
**Terraform Version**: 1.6.0+
**AWS Provider Version**: ~> 5.0
