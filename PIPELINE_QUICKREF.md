# GitOps Pipeline - Quick Reference

## Pipeline Overview

```
Feature Branch
       ↓
  Create PR
       ↓
Terraform Plan (Auto) + EKS Validation (Auto)
       ↓
  Review Plan
       ↓
  Merge to Main
       ↓
Manual Apply (Requires Approval)
       ↓
Drift Detection (Daily or Manual)
       ↓
EKS Health Check (Every 6 hours)
```

## Workflow Status Badges

Add these to your README.md:

```markdown
[![Terraform PR](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/terraform-pr.yaml/badge.svg)](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/terraform-pr.yaml)
[![Terraform Apply](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/terraform-apply.yaml/badge.svg?branch=main)](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/terraform-apply.yaml)
[![Drift Detection](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/terraform-drift-detection.yaml/badge.svg)](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/terraform-drift-detection.yaml)
[![EKS Validation](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/eks-validation.yaml/badge.svg)](https://github.com/YOUR_ORG/vprofile-infra/actions/workflows/eks-validation.yaml)
```

## Quick Setup Checklist

- [ ] Create GitHub secrets (AWS_ROLE_TO_ASSUME, TF_BACKEND_BUCKET, etc.)
- [ ] Create AWS OIDC identity provider
- [ ] Create IAM role for GitHub Actions (github-oidc-role)
- [ ] Create S3 bucket for Terraform state
- [ ] Create DynamoDB table for state locking
- [ ] Create environment protection rules in GitHub
- [ ] Set up Slack webhook (optional)
- [ ] Create branch protection rules on main
- [ ] Test with feature branch
- [ ] Perform first approval and deploy

## Common Commands

### Git Workflow
```bash
# Create feature branch
git checkout -b feature/update-eks

# Make changes
vim main.tf

# Commit and push
git add *.tf
git commit -m "Update EKS cluster configuration"
git push origin feature/update-eks

# Create PR on GitHub
# Wait for automatic validation...
# Approve and merge

# Workflow applies automatically after human approval
```

### Local Testing
```bash
# Initialize Terraform
terraform init -backend-config="bucket=$TF_BACKEND_BUCKET" ...

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Show plan
terraform show tfplan

# Apply
terraform apply tfplan

# Destroy (for testing only)
terraform destroy
```

### Manual Drift Detection
```bash
# Trigger from GitHub Actions UI:
1. Go to Actions tab
2. Select "Terraform Drift Detection"
3. Click "Run workflow"
4. Select main branch
5. Click "Run workflow"

# Or via GitHub CLI:
gh workflow run terraform-drift-detection.yaml --ref main --input "notify_slack=true"
```

### View Deployment History
```bash
# Using GitHub CLI
gh run list -w terraform-apply.yaml -L 10

# View specific run
gh run view <run-id> --log

# Download artifacts
gh run download <run-id> -n terraform-apply-<run-id>
```

## Monitoring and Status

### Check Workflow Status
- Dashboard: GitHub → Actions
- Filter: Main branch, all workflows
- Details: Click any workflow run
- Logs: Click "View more details" or expand steps

### Artifacts Location
- **Plan artifacts**: Actions → Run → Artifacts
- **Drift reports**: Actions → Latest drift run → Artifacts
- **EKS validation**: Actions → Latest validation run → Artifacts

### Notifications
- **PR Comments**: Auto-posted plan summary
- **Slack Messages**: On drift, apply, validation
- **GitHub Issues**: Auto-created on drift detection
- **Email**: Configure in GitHub settings

## Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| OIDC auth fails | Check role trust policy subject format |
| Plan fails | Verify S3 and DynamoDB access permissions |
| EKS connection issues | Check kubeconfig and cluster security groups |
| Slack notification fails | Verify webhook URL in secrets |
| No drift alerts | Check cron schedule and Slack webhook |
| Slow validations | May exceed GitHub Actions timeout (6 hours) |

## Environment Configuration

### Variable Defaults vs. Secrets
- Use GitHub Secrets for sensitive values
- Use Terraform variables.tf for defaults
- Workflows merge both automatically

Example:
```yaml
# workflow uses both:
- name: Terraform Init
  run: |
    terraform init \
      -backend-config="bucket=${{ secrets.TF_BACKEND_BUCKET }}" \
      -backend-config="region=${{ secrets.AWS_REGION || 'us-east-1' }}"
```

## Cost Considerations

- **EKS Cluster**: ~$73/month
- **GitHub Actions**: 2,000 free minutes/month (included)
- **S3 State Storage**: <$1/month
- **DynamoDB Locking**: <$1/month
- **Slack Webhooks**: Free

**Estimated Monthly Cost**: $75-100

## Security Best Practices

1. ✅ Use OIDC federation (no long-lived credentials)
2. ✅ Require manual approval for main branch
3. ✅ Enable branch protection rules
4. ✅ Encrypt Terraform state in S3
5. ✅ Use DynamoDB state locking
6. ✅ Audit IAM role permissions
7. ✅ Review and approve all PRs
8. ✅ Monitor drift alerts closely

## Support Resources

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Terraform State Management](https://www.terraform.io/language/state)

## Emergency Procedures

### Emergency Apply (Max 10 minutes)
```bash
# If GitHub Actions is down:
1. Use local AWS credentials
2. Run: terraform apply
3. Post-apply: Commit tfstate changes
```

### Rollback Previous State
```bash
# 1. Find previous good state version
aws s3api list-object-versions \
  --bucket your-bucket \
  --key vprofile-infra/terraform.tfstate

# 2. Restore previous version
aws s3api copy-object \
  --bucket your-bucket \
  --copy-source your-bucket/vprofile-infra/terraform.tfstate?versionId=xxx \
  --key vprofile-infra/terraform.tfstate

# 3. Run terraform plan to see changes
terraform plan

# 4. Apply rollback
terraform apply
```

### Drift Resolution
```bash
# If drift is found but not desired:
1. Check AWS changes
2. Run: terraform refresh
3. Commit changes if needed
4. Or: terraform import to sync state

# If drift should be applied:
1. Manually approve in GitHub Actions
2. Click "Apply" button
3. Drift will be corrected
```

## Monitoring and Alerts

### Recommended Monitoring
- [ ] Enable GitHub email notifications
- [ ] Set up Slack alerts (see PIPELINE_CONFIG.md)
- [ ] Subscribe to drift detection issues
- [ ] Configure CloudWatch alarms for EKS
- [ ] Review cost reports monthly

### Key Metrics to Track
- Deploy frequency
- Deployment duration
- Drift detection rate
- Failed validations
- Manual approval delays

---

**Quick Links**:
- [Full Setup Guide](./PIPELINE_SETUP.md)
- [Configuration Guide](./PIPELINE_CONFIG.md)
- [Terraform Files](./main.tf)
