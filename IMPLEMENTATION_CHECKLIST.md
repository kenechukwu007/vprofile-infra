# Implementation Checklist - Terraform GitOps Pipeline

Use this checklist to implement the vprofile-infra GitOps pipeline step by step.

## Phase 1: AWS Setup

### IAM Configuration

- [ ] **Create OIDC Identity Provider**
  ```bash
  # Check if already exists
  aws iam list-open-id-connect-providers
  
  # If not, GitHub will prompt to create during first workflow run
  # Or manually: Settings → Developer Settings → OAuth Apps → GitHub Actions
  ```
  
- [ ] **Create IAM Role: github-oidc-role**
  - [ ] Role name: `github-oidc-role`
  - [ ] Trust entity: Web Identity
  - [ ] Provider: token.actions.githubusercontent.com
  - [ ] Audience: sts.amazonaws.com
  - [ ] Subject: repo:YOUR_ORG/vprofile-infra:*

- [ ] **Attach Policies to github-oidc-role**
  - [ ] S3 access (state bucket)
  - [ ] DynamoDB access (lock table)
  - [ ] EKS permissions
  - [ ] IAM permissions
  - [ ] VPC/EC2 permissions
  - [ ] Review in PIPELINE_CONFIG.md for detailed policy

- [ ] **Get Role ARN**
  ```bash
  aws iam get-role --role-name github-oidc-role --query 'Role.Arn'
  # Expected: arn:aws:iam::123456789:role/github-oidc-role
  ```

### Terraform Backend Setup

- [ ] **Create S3 Bucket for State**
  ```bash
  aws s3api create-bucket \
    --bucket vprofile-terraform-state \
    --region us-east-1
  
  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket vprofile-terraform-state \
    --versioning-configuration Status=Enabled
  
  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket vprofile-terraform-state \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'
  
  # Block public access
  aws s3api put-public-access-block \
    --bucket vprofile-terraform-state \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  ```

- [ ] **Create DynamoDB Table for State Locking**
  ```bash
  aws dynamodb create-table \
    --table-name terraform-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region us-east-1
  ```

- [ ] **Verify Backend Access**
  ```bash
  # Try listing state bucket
  aws s3 ls vprofile-terraform-state/
  
  # Try DynamoDB table
  aws dynamodb describe-table --table-name terraform-locks
  ```

### EKS Cluster Verification

- [ ] **Verify Cluster Exists**
  ```bash
  aws eks describe-cluster --name vprofile-eks-cluster --query 'cluster.name'
  ```

- [ ] **Test Cluster Access**
  ```bash
  aws eks update-kubeconfig --name vprofile-eks-cluster
  kubectl cluster-info
  kubectl get nodes
  ```

- [ ] **Verify ArgoCD Installation**
  ```bash
  kubectl get namespace argocd
  kubectl get pods -n argocd
  ```

---

## Phase 2: GitHub Configuration

### Repository Setup

- [ ] **Clone Repository Locally**
  ```bash
  git clone https://github.com/YOUR_ORG/vprofile-infra.git
  cd vprofile-infra
  ```

- [ ] **Verify .github/workflows Exists**
  ```bash
  # Should contain 4 files:
  ls -la .github/workflows/
  # - terraform-pr.yaml
  # - terraform-apply.yaml
  # - terraform-drift-detection.yaml
  # - eks-validation.yaml
  ```

- [ ] **Commit Workflow Files**
  ```bash
  git add .github/workflows/
  git add PIPELINE_SETUP.md PIPELINE_CONFIG.md PIPELINE_QUICKREF.md
  git commit -m "Add GitOps Terraform pipeline workflows"
  git push origin main
  ```

### GitHub Secrets Configuration

- [ ] **Navigate to Secrets Settings**
  - Go to: Settings → Secrets and variables → Actions

- [ ] **Add Required Secrets** (one by one)
  ```
  Name: AWS_ROLE_TO_ASSUME
  Value: arn:aws:iam::YOUR_ACCOUNT:role/github-oidc-role
  ```
  
  ```
  Name: TF_BACKEND_BUCKET
  Value: vprofile-terraform-state
  ```
  
  ```
  Name: TF_BACKEND_KEY
  Value: vprofile-infra/terraform.tfstate
  ```
  
  ```
  Name: TF_BACKEND_DYNAMODB
  Value: terraform-locks
  ```
  
  ```
  Name: AWS_REGION
  Value: us-east-1
  ```
  
  ```
  Name: EKS_CLUSTER_NAME
  Value: vprofile-eks-cluster
  ```

- [ ] **Add Optional Secrets**
  ```
  Name: SLACK_WEBHOOK
  Value: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
  (Leave empty if not using Slack)
  ```

### GitHub Environment Setup

- [ ] **Create "production" Environment**
  - Go to: Settings → Environments → New environment
  - Environment name: `production`

- [ ] **Configure Deployment Branches**
  - Deployment branches: `Restrict to main branch`

- [ ] **Add Required Reviewers**
  - [ ] Enable "Required reviewers"
  - [ ] Add team members who can approve deployments
  - Recommended: 1-2 senior engineers

- [ ] **Configure Protection Rules**
  - [ ] Prevent self-review (optional)
  - [ ] Limit deployment branches to main

### Branch Protection Rules

- [ ] **Go to Settings → Branches**

- [ ] **Create Rule for "main" Branch**
  - [ ] Branch name pattern: `main`
  - [ ] Require pull request reviews before merging
  - [ ] Require status checks to pass:
    - `Terraform Validate & Plan on PR` (terraform-validate-plan)
    - `EKS Validation` (eks-validation)
  - [ ] Require code reviews: 2 approvals
  - [ ] Require conversation resolution
  - [ ] Allow auto-merge: No (keep manual)
  - [ ] Require branches up to date before merging

---

## Phase 3: Test the Pipeline

### Test 1: Create Feature Branch and PR

- [ ] **Create Test Branch**
  ```bash
  git checkout -b test/pipeline-validation
  
  # Make a small, non-breaking change
  echo "# Test comment" >> main.tf
  
  git add main.tf
  git commit -m "Test: Pipeline validation"
  git push origin test/pipeline-validation
  ```

- [ ] **Create Pull Request**
  - Go to GitHub and create PR to main
  - Title: "Test: Validate pipeline workflows"

- [ ] **Monitor PR Validation**
  - [ ] Watch Actions tab
  - [ ] Should see: terraform-pr workflow running
  - [ ] Check for: Plan posted to PR comments
  - [ ] Check for: EKS validation completed
  - [ ] Accept status checks before merging

- [ ] **Review Plan in PR** (Expected: No infrastructure changes)
  ```
  Plan: 0 to add, 0 to change, 0 to destroy
  ```

- [ ] **Approve and Merge PR**
  - Approve as reviewer
  - Click "Squash and merge"
  - Confirm merge

### Test 2: Monitor Apply Workflow

- [ ] **Go to Actions Tab**
  - Select "Terraform Apply (Manual)"
  - Should see new run triggered by merge

- [ ] **Review Deployment Protection**
  - Click on run
  - Should see: "Waiting for manual approval"
  - Should see: "Review deployments" button

- [ ] **Approve Apply**
  - Click "Review deployments"
  - Select production environment
  - Click "Approve and deploy"
  - Confirm action

- [ ] **Monitor Apply Execution**
  - [ ] Check step-by-step execution
  - [ ] Verify: terraform apply runs
  - [ ] Verify: state is updated
  - [ ] Look for completion message

- [ ] **Verify No Changes Applied**
  - Since this is a test with no real changes
  - Should show: "No changes. Infrastructure is up-to-date."

### Test 3: Drift Detection

- [ ] **Manually Trigger Drift Detection**
  - Go to Actions tab
  - Select "Terraform Drift Detection"
  - Click "Run workflow"
  - Select main branch
  - Click "Run workflow"

- [ ] **Monitor Drift Workflow**
  - [ ] Should run successfully
  - [ ] Should show: STATE REFRESH COMPLETE
  - [ ] Should show: NO DRIFT DETECTED (for test)

- [ ] **Check Artifacts**
  - Click workflow run
  - Go to Artifacts
  - Download drift-report

### Test 4: EKS Validation

- [ ] **Manually Trigger EKS Validation**
  - Actions → EKS Cluster Validation
  - Run workflow

- [ ] **Monitor Validation**
  - [ ] Cluster info retrieved
  - [ ] Nodes listed
  - [ ] ArgoCD status checked
  - [ ] Ingress validated
  - [ ] All checks should pass

- [ ] **Review Report**
  - Download eks-validation-report artifact
  - Verify all components are operational

### Test 5: Cleanup Test Branch

- [ ] **Delete Test Branch**
  ```bash
  git push origin --delete test/pipeline-validation
  ```

- [ ] **Verify Main Branch Stable**
  - Latest commit should be test commit
  - No failed workflows

---

## Phase 4: Production Readiness

### Documentation

- [ ] **Update README.md**
  - Add workflow badges
  - Add link to PIPELINE_SETUP.md
  - Add "Deployment" section
  - Example:
    ```markdown
    ## Deployment
    
    This repository uses a GitOps pipeline for infrastructure management.
    
    [![Terraform PR](link-to-badge)](link-to-workflow)
    [![Drift Detection](link-to-badge)](link-to-workflow)
    
    See [PIPELINE_SETUP.md](PIPELINE_SETUP.md) for complete documentation.
    ```

- [ ] **Document Team Procedures**
  - Create CONTRIBUTING.md with:
    - How to create feature branches
    - How to create PRs
    - How to review plans
    - How to approve deployments
    - Who can approve

- [ ] **Create Runbook**
  - Emergency procedures
  - Rollback steps (see PIPELINE_QUICKREF.md)
  - Troubleshooting guide
  - Escalation contacts

### Team Training

- [ ] **Train Team Members**
  - [ ] How to read Terraform plans
  - [ ] How to approve deployments
  - [ ] How to investigate drift
  - [ ] Emergency procedures

- [ ] **Create Team Access**
  - [ ] Add CODEOWNERS file:
    ```
    * @infrastructure-team
    ```
  - [ ] Add required reviewers:
    - [ ] Settings → Environments → production
    - [ ] Add team members

### Monitoring Setup

- [ ] **Slack Channel Setup** (Optional)
  - [ ] Create #infrastructure-deployments channel
  - [ ] Create webhook
  - [ ] Add SLACK_WEBHOOK secret

- [ ] **CloudWatch Alarms**
  - [ ] EKS cluster health
  - [ ] Node status
  - [ ] Pod restart count

- [ ] **GitHub Alerts**
  - [ ] Enable branch notifications
  - [ ] Watch drift detection issues
  - [ ] Subscribe to workflow failures

### Backup and Recovery

- [ ] **Backup Plan**
  - [ ] S3 state bucket has versioning (✓ already done)
  - [ ] Regular backups of kubeconfig
  - [ ] Document restore procedures

- [ ] **Disaster Recovery Test**
  - [ ] Can restore from state backup?
  - [ ] Can restore from kubeconfig?
  - [ ] Is documentation current?

---

## Phase 5: Going Live

### Pre-Launch Checklist

- [ ] All tests passed successfully
- [ ] Team trained and ready
- [ ] Documentation complete
- [ ] Slack notifications working
- [ ] Backup procedures documented
- [ ] Emergency procedures documented
- [ ] At least 2 team members can approve

### Launch Day

- [ ] **Announce to Team**
  - New GitOps pipeline is live
  - All infrastructure changes go through GitHub
  - No direct AWS changes

- [ ] **Monitor Closely**
  - [ ] Watch Actions tab
  - [ ] Monitor Slack alerts
  - [ ] Check CloudWatch
  - [ ] Be available for 24 hours

- [ ] **Log Issues Found**
  - Create GitHub issues for any problems
  - Document solutions
  - Update runbook

### Post-Launch (First Week)

- [ ] **Performance Review**
  - Deployment time
  - Approval time
  - Any manual interventions needed

- [ ] **Process Improvements**
  - Streamline approval process if needed
  - Adjust cron schedules based on load
  - Add additional validators if needed

- [ ] **Team Feedback**
  - Collect feedback from team
  - Update procedures based on feedback
  - Document lessons learned

---

## Ongoing Maintenance

### Weekly Tasks
- [ ] Review drift detection alerts
- [ ] Monitor failed workflows
- [ ] Check GitHub Actions usage

### Monthly Tasks
- [ ] Review IAM permissions
- [ ] Audit state file access
- [ ] Update documentation
- [ ] Test disaster recovery

### Quarterly Tasks
- [ ] Update Terraform version
- [ ] Update AWS provider version
- [ ] Review AWS costs
- [ ] Security audit

---

## Troubleshooting Reference

| Issue | Solution | Status |
|-------|----------|--------|
| OIDC auth fails | Check role trust policy subject | See PIPELINE_CONFIG.md |
| S3 access denied | Check IAM policy and tag-based access | See AWS IAM Policy |
| kubectl fails | Check kubeconfig and EKS security groups | See PIPELINE_SETUP.md |
| Plan fails | Check Terraform syntax and backend config | See PIPELINE_QUICKREF.md |
| Slack webhook fails | Verify webhook URL in secrets | See PIPELINE_CONFIG.md |
| No drift alerts | Check cron schedule and Slack webhook | See PIPELINE_SETUP.md |

---

## Quick Links
- [Complete Setup Guide](./PIPELINE_SETUP.md)
- [Configuration Guide](./PIPELINE_CONFIG.md)
- [Quick Reference](./PIPELINE_QUICKREF.md)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Terraform Docs](https://www.terraform.io/docs)

---

**Status**: Use this as your implementation tracking document.
**Target Completion**: Fill in actual dates as you complete each phase.
**Last Updated**: Phase Planning Complete

