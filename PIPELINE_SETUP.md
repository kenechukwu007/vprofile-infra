# Terraform GitOps Pipeline Setup Guide

This document provides complete setup instructions for the vprofile-infra Terraform GitOps pipeline.

## Overview

The pipeline consists of 4 automated workflows:

1. **Terraform PR Validation** - Validates and plans on PR creation
2. **Terraform Apply** - Manual approval gate for main branch changes
3. **Drift Detection** - Detects infrastructure drift (daily)
4. **EKS Validation** - Validates cluster health and configuration

## Prerequisites

- GitHub repository with Actions enabled
- AWS account with appropriate permissions
- EKS cluster deployed (vprofile-eks-cluster)
- ArgoCD installed on the cluster
- Terraform S3 backend configured
- GitHub Secrets configured (see below)

## GitHub Secrets Configuration

Add these secrets to your GitHub repository (Settings → Secrets and Variables → Actions):

### Required Secrets

```
AWS_ROLE_TO_ASSUME
  Value: arn:aws:iam::YOUR_ACCOUNT_ID:role/github-oidc-role
  Description: IAM role for GitHub Actions OIDC federation

TF_BACKEND_BUCKET
  Value: your-terraform-state-bucket
  Description: S3 bucket for Terraform state

TF_BACKEND_KEY
  Value: vprofile-infra/terraform.tfstate
  Description: Path to state file in S3

TF_BACKEND_DYNAMODB
  Value: terraform-locks
  Description: DynamoDB table for state locking

AWS_REGION
  Value: us-east-1
  Description: AWS region (optional, defaults to us-east-1)

EKS_CLUSTER_NAME
  Value: vprofile-eks-cluster
  Description: EKS cluster name (optional)

SLACK_WEBHOOK
  Value: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
  Description: Slack webhook for notifications (optional)
```

## AWS IAM Setup (OIDC Federation)

### Create OIDC Identity Provider

```bash
# Set your GitHub organization and repository
GITHUB_ORG="your-org"
GITHUB_REPO="vprofile-infra"
AWS_ACCOUNT_ID="your-account-id"

# Create trust policy
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:GITHUB_ORG/GITHUB_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name github-oidc-role \
  --assume-role-policy-document file:///tmp/trust-policy.json

# Attach permissions for Terraform
aws iam attach-role-policy \
  --role-name github-oidc-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Or use a custom policy (recommended)
cat > /tmp/terraform-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "iam:*",
        "s3:*",
        "dynamodb:*",
        "kms:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name github-oidc-role \
  --policy-name terraform-policy \
  --policy-document file:///tmp/terraform-policy.json
```

## Terraform Backend Configuration

Create S3 bucket and DynamoDB table if not exists:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1 \
  --create-bucket-configuration LocationConstraint=us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

## Workflow Descriptions

### 1. Terraform PR Validation (`terraform-pr.yaml`)

**Triggers**: On PR to main branch with `.tf` file changes

**Steps**:
1. Checkout code
2. Configure AWS credentials via OIDC
3. Validate Terraform formatting
4. Initialize Terraform backend
5. Run `terraform validate`
6. Run `terraform plan` and post results to PR
7. Validate against EKS cluster
8. Store plan artifact

**Outputs**:
- Plan summary in PR comments
- Plan artifact for later use
- EKS cluster validation results

### 2. Terraform Apply (`terraform-apply.yaml`)

**Triggers**: After successful merge to main

**Steps**:
1. Checkout code
2. Initialize Terraform
3. Run `terraform plan`
4. **Waits for manual approval** (via GitHub environment protection)
5. Run `terraform apply`
6. Post results to commit
7. Send Slack notification

**Manual Approval**:
- Click "Review deployments" in the workflow run
- Approve or reject the changes
- Only then apply will proceed

### 3. Drift Detection (`terraform-drift-detection.yaml`)

**Triggers**: 
- Daily at 2 AM UTC (configurable)
- Manual trigger via workflow_dispatch

**Steps**:
1. Refresh Terraform state from AWS
2. Run `terraform plan` to detect drift
3. If drift detected:
   - Create GitHub issue with details
   - Post Slack alert
   - Store report artifact

**Benefits**:
- Detects manual AWS changes
- Identifies ArgoCD conflicting deployments
- Alerts on external modifications

### 4. EKS Validation (`eks-validation.yaml`)

**Triggers**:
- Every 6 hours
- After successful apply
- Manual trigger

**Validates**:
- Cluster connectivity
- Node status
- ArgoCD installation
- ALB Ingress controller
- EBS CSI driver
- Storage classes
- Security groups
- RBAC configuration
- DNS resolution

## Usage Workflow

### 1. Create a Feature Branch
```bash
git checkout -b feature/update-eks-cluster
# Make Terraform changes
git add *.tf
git commit -m "Update EKS cluster configuration"
git push origin feature/update-eks-cluster
```

### 2. Create Pull Request
- Go to GitHub and create PR to `main`
- Terraform PR workflow will automatically:
  - Validate formatting
  - Run `terraform validate`
  - Generate and post plan to PR
  - Validate against EKS cluster

### 3. Review and Merge
- Review the plan in PR comments
- Address any issues
- Get approval from reviewers
- Merge to main

### 4. Manual Apply
- Merged commit triggers manual apply workflow
- Click "Review deployments" in GitHub Actions
- Review the plan one more time
- Click "Approve and deploy"
- Terraform apply runs automatically

### 5. Drift Detection
- Automatic daily check at 2 AM UTC
- If drift detected, GitHub issue created automatically
- Slack alert sent
- Can trigger manually anytime

## Troubleshooting

### Authentication Issues
```
Error: "not authorized to perform: sts:AssumeRoleWithWebIdentity"
```
**Solution**: Check OIDC role trust policy and ensure subject matches repo

### Terraform State Lock
```
Error: Error acquiring the state lock
```
**Solution**: Check DynamoDB table exists and has proper permissions

### EKS Connection Issues
```
error: unable to access the server
```
**Solution**: Ensure kubeconfig is updated and cluster security groups allow GitHub Actions IP

### Slack Webhook Failed
```
Webhook URL is not valid
```
**Solution**: Copy webhook URL correctly from Slack workspace settings

## Environment Protection Rules

To enforce manual approval:

1. Go to repository Settings → Environments
2. Create/Edit "production" environment
3. Enable "Required reviewers"
4. Add team members who can approve deployments
5. Required reviewers will be notified before apply

## Monitoring and Logs

### View Workflow Runs
```
GitHub Actions → Select workflow → View run logs
```

### Common Log Locations
- PR Validation: `Actions → terraform-pr.yaml`
- Apply Process: `Actions → terraform-apply.yaml`
- Drift Reports: `Artifacts → drift-report-*`
- EKS Validation: `Artifacts → eks-validation-report-*`

### Debugging Commands
```bash
# Check state file
terraform show

# Validate configuration
terraform validate

# Plan with verbose output
TF_LOG=DEBUG terraform plan

# Read specific resource
terraform state show aws_eks_cluster.this
```

## Security Best Practices

1. **Limit OIDC Permissions**
   - Create minimal IAM policy
   - Only grant needed AWS services
   - Use resource-level restrictions

2. **Environment Protection**
   - Require multiple reviewers
   - Enforce status checks
   - Use branch protection rules

3. **Secrets Management**
   - Rotate OIDC credentials regularly
   - Use short-lived tokens (default: 1 hour)
   - Never commit secrets to repo

4. **Audit Trail**
   - Review all deployments in GitHub
   - Check CloudTrail for AWS changes
   - Monitor Slack notifications

5. **State File Security**
   - Enable S3 versioning
   - Enable encryption
   - Use DynamoDB for locking
   - Restrict IAM access to state

## Cost Optimization

1. **Reduce Validation Frequency**
   - Adjust cron schedules as needed
   - Use manual triggers for testing

2. **Cleanup Artifacts**
   - Set retention periods (default: 5-30 days)
   - Archive old reports

3. **Monitor AWS Usage**
   - Review EKS cluster costs
   - Optimize resource sizing
   - Use spot instances for non-production

## Next Steps

1. ✅ Add GitHub secrets
2. ✅ Create OIDC role in AWS
3. ✅ Test with feature branch
4. ✅ Review first PR plan
5. ✅ Perform first manual deployment
6. ✅ Monitor drift detection alerts
7. ✅ Set up environment protection rules

## Support and References

- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Backend S3](https://www.terraform.io/language/settings/backends/s3)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
