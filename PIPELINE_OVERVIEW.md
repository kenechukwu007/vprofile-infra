# vprofile-infra Terraform GitOps Pipeline - Overview

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TERRAFORM GITOPS PIPELINE                            │
└─────────────────────────────────────────────────────────────────────────┘

FEATURE BRANCH WORKFLOW:
═══════════════════════

    Developer
        │
        │ git checkout -b feature/update
        │ vim main.tf
        │ git push origin feature
        ▼
    Create Pull Request
        │
        ├─────────────────────────────────────────────────┐
        │                                                 │
        ▼                                                 ▼
    Terraform Validate                           EKS Cluster Check
    Terraform Format Check            (Connectivity & compatibility)
    Terraform Plan                    
    └──► Post Plan to PR ◄────────────────────┘
        │
        │ Review plan in PR comments
        │ Approve if changes look good
        │
        ▼
    Merge to Main
        │
        │ Triggers automatically
        │
        ├─────────────────────────────────────────────────┐
        │                                                 │
        ▼                                                 ▼
    terraform plan -out=tfplan              🔒 PROTECTION GATE
        │                                   Requires manual approval
        │                                   from authorized reviewers
        ▼
    ⏸️  AWAITING APPROVAL ⏸️
        │
        │ Team Lead Reviews
        │ Clicks "Review deployments"
        │ Approves changes
        │
        ▼
    terraform apply ✅
        │
        ├─────────────────────────────────────────────────┐
        │                                                 │
        ▼                                                 ▼
    Infrastructure Updated              Slack Notification
    State File Updated                  (Success alert)
        │
        │ Auto-triggers drift detection
        │ (checks if changes match desired state)
        │
        └─────────────────────────────────────────────────┐


DRIFT DETECTION WORKFLOW:
════════════════════════

Daily Schedule (2 AM UTC)
Manual Trigger (Anytime)
         │
         ▼
    Refresh Terraform State
    (Re-reads actual AWS resources)
         │
         ▼
    terraform plan
    (Compare desired vs actual)
         │
         ├─── NO DRIFT DETECTED (✅) ─────┐
         │                                 │
         └─── DRIFT DETECTED (⚠️) ─────┐  │
              │                        │  │
              │ Create GitHub Issue    │  │ Post Slack Success
              │ Alert Team            │  │ Message
              │                        │  │
              └────────────┬───────────┘  │
                           │              │
                           ▼              ▼
                        Team Investigates
                        Takes Action:
                        • Apply changes via manual approve
                        • Manual AWS sync
                        • Update Terraform config


EKS VALIDATION WORKFLOW:
═══════════════════════

Every 6 Hours (Scheduled)
After Apply (Triggered)
Manual Run (Anytime)
         │
         ▼
    ✓ Cluster Connectivity Test
    ✓ Node Status Check
    ✓ ArgoCD Installation Verification
    ✓ ALB Ingress Controller Check
    ✓ EBS CSI Driver Validation
    ✓ Storage Classes Review
    ✓ Security Group Configuration
    ✓ RBAC & Service Accounts
    ✓ DNS Resolution Test
         │
         ├─── ALL CHECKS PASS (✅) ─────┐
         │                              │
         └─── SOME CHECKS FAIL (⚠️) ──┐ │
              │                       │ │
              │ Alert Team           │ │ Post Success
              │ Generate Report      │ │ Notification
              │                      │ │
              └──────────┬───────────┘ │
                         │             │
                         ▼             ▼
                    Team Investigates  No Action
                    Fixes Issues       Needed


BRANCH PROTECTION:
═════════════════

Main Branch Requirements:
├─ ✓ Status checks must pass
│  ├─ Terraform PR validation
│  └─ EKS validation
├─ ✓ Pull request reviews (2 required)
├─ ✓ Conversation resolution
├─ ✓ Branches must be up to date
├─ ✓ Explicit approval required
└─ ✓ No self-review allowed


STATE MANAGEMENT:
════════════════

Terraform State Storage:
    ┌───────────────────────────────────────┐
    │    AWS S3 Bucket                      │
    │  (terraform-state)                    │
    │                                       │
    │  Features:                            │
    │  ✓ Versioning enabled                 │
    │  ✓ Encryption enabled (AES-256)      │
    │  ✓ Public access blocked              │
    │  ✓ MFA delete enabled                 │
    └───────────────────────────────────────┘
                    │
                    │ Locking mechanism
                    ▼
    ┌───────────────────────────────────────┐
    │    AWS DynamoDB Table                 │
    │  (terraform-locks)                    │
    │                                       │
    │  Purpose:                             │
    │  ✓ Prevent concurrent applies        │
    │  ✓ Detect stale locks                │
    │  ✓ Track operation timing            │
    └───────────────────────────────────────┘


AUTHENTICATION & AUTHORIZATION:
═══════════════════════════════

    GitHub Actions
        │
        │ Requests temporary credentials
        │
        ▼
    AWS OIDC Provider
    (token.actions.githubusercontent.com)
        │
        │ Validates GitHub workflow
        │ Checks subject claim
        │ Issues temporary token
        │
        ▼
    IAM Role: github-oidc-role
    (No long-lived credentials!)
        │
        ├─ S3 access (state bucket)
        ├─ DynamoDB access (locks)
        ├─ EKS access (validation)
        ├─ IAM access (role management)
        ├─ EC2 access (VPC resources)
        └─ CloudWatch access (logs)
        │
        ▼
    AWS Resources
    (Fully Scoped, Temporary Access)
```

## File Structure

```
vprofile-infra/
├── main.tf                          # EKS cluster definition
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── backend.tf                       # S3 backend config
├── agrocd-ingress.yaml              # ArgoCD Ingress resource
├── .gitignore                       # Git ignore patterns
│
├── .github/
│   └── workflows/
│       ├── terraform-pr.yaml        # ✓ Validate & Plan on PR
│       ├── terraform-apply.yaml     # ✓ Manual Apply with approval
│       ├── terraform-drift-detection.yaml  # ✓ Daily drift check
│       └── eks-validation.yaml      # ✓ Cluster health validation
│
├── Documentation/
│   ├── PIPELINE_SETUP.md            # Complete setup guide
│   ├── PIPELINE_CONFIG.md           # Configuration reference
│   ├── PIPELINE_QUICKREF.md         # Quick reference
│   ├── IMPLEMENTATION_CHECKLIST.md  # Step-by-step checklist
│   └── PIPELINE_OVERVIEW.md         # This file
│
└── README.md                        # Main project README
```

## Key Workflows Explained

### 1️⃣ PR Validation (terraform-pr.yaml)

**Trigger**: Pull Request to main branch

**Steps**:
1. Checkout code
2. Configure AWS OIDC credentials
3. Validate Terraform formatting
4. Initialize backend
5. Run terraform validate
6. Generate terraform plan
7. Post plan summary to PR
8. Validate against EKS cluster
9. Store plan artifact

**Approval Gates**: None (informational only)

**Posting**: Plan details in PR comments

**Duration**: ~3-5 minutes

---

### 2️⃣ Apply with Approval (terraform-apply.yaml)

**Trigger**: Merged commit to main

**Steps**:
1. Checkout code
2. Configure AWS OIDC credentials
3. Initialize backend
4. Generate terraform plan
5. ⏸️ **PAUSE - Awaiting Approval** ⏸️
   - Developer triggers "Review deployments"
   - Selects "production" environment
   - Clicks "Approve and deploy"
   - Required reviewers are notified
6. terraform apply (runs after approval)
7. Post results to commit
8. Send Slack notification
9. Trigger drift detection

**Approval Gates**: 
- GitHub environment protection (1-2 reviewers)
- Manual approval via "Review deployments" button

**Duration**: Manual approval + ~5-10 minutes for apply

---

### 3️⃣ Drift Detection (terraform-drift-detection.yaml)

**Trigger**:
- Daily at 2:00 AM UTC
- After successful apply
- Manual trigger anytime

**Steps**:
1. Refresh Terraform state (re-reads AWS)
2. Run terraform plan
3. If drift detected:
   - Create GitHub issue with details
   - Post Slack alert
   - Notify team for action
4. If no drift:
   - Log success
   - Post success notification

**Auto-Actions**:
- Creates issues automatically when drift found
- Sends Slack alerts
- Stores detailed reports

**Duration**: ~2-3 minutes

---

### 4️⃣ EKS Validation (eks-validation.yaml)

**Trigger**:
- Every 6 hours (scheduled)
- After apply completes
- Manual trigger

**Validates**:
- Cluster connectivity
- Node status and resources
- ArgoCD installation
- ALB Ingress controller
- EBS CSI driver
- Storage classes
- Security group rules
- RBAC configuration
- DNS resolution

**Reports**:
- Comprehensive validation report
- Slack notifications
- Artifact storage

**Duration**: ~1-2 minutes

---

## State of the System at Each Step

### Step 1: Feature Branch Created
```
Status: Development
- PR validation: ✓ RUNNING
- Changes: Not yet in production
- State: Unchanged
```

### Step 2: PR Comments Posted
```
Status: Review
- PR validation: ✓ PASSED
- Plan: Available in PR comments
- State: Unchanged
- Action: Awaiting human review & approval
```

### Step 3: PR Merged to Main
```
Status: Pre-Release
- PR workflow: ✓ COMPLETE
- Apply workflow: ✓ RUNNING
- State: Not yet applied
- Action: Awaiting manual approval
```

### Step 4: Apply Approved
```
Status: Releasing
- Apply workflow: ✓ APPLYING
- State: Being updated
- Action: Terraform apply running
```

### Step 5: Apply Complete
```
Status: Released ✓
- Infrastructure: Updated
- State: Committed
- Drift Detection: Auto-triggered
- Action: Monitoring drift
```

### Step 6: Drift Detection Results
```
Status: Monitoring (No Drift)
- State: Stable ✓
- Configuration: Matches AWS
- Next Check: Tomorrow 2 AM
```

---

## Communication Flow

```
Developer
   │
   ├─► GitHub (Create PR)
   │
   ├─► GitHub (Approve)
   │
   ├─► GitHub (Merge)
   │
   ├─► GitHub Actions (See plan)
   │
   ├─► Reviewers (Notify for approval)
   │
   ├─► GitHub (Click "Approve and deploy")
   │
   ├─► AWS (Apply infrastructure)
   │
   ├─► Slack (Notify on success)
   │
   ├─► GitHub (Post results)
   │
   └─► Team (Review drift report daily)
```

---

## Security Layers

```
1. GitHub Security
   ├─ Branch protection rules
   ├─ Required reviewers (2)
   ├─ Environment protection
   └─ Signed commits (enforced)

2. AWS IAM Security
   ├─ OIDC federation (no static credentials)
   ├─ Temporary token (1 hour max)
   ├─ Role-based access control
   └─ Resource-based policies

3. Terraform Security
   ├─ State file encryption (AES-256)
   ├─ State file versioning
   ├─ Concurrent access lock
   └─ Audit trail via S3

4. Kubernetes Security
   ├─ RBAC policies
   ├─ Service account roles
   ├─ Network policies
   └─ Security groups
```

---

## Success Criteria

✅ **Workflow Success** when:
- [ ] All status checks pass on PR
- [ ] Plan shows expected changes
- [ ] Code reviewers approve
- [ ] Manual approval given for apply
- [ ] Terraform apply completes
- [ ] No drift detected 24 hours later
- [ ] EKS cluster remains healthy

---

## Common Scenario Flows

### Scenario 1: Update EKS Node Group Size

```
1. Create branch: feature/scale-nodes
2. Update main.tf: desired_size = 4
3. Create PR
4. → terraform-pr workflow validates (✓)
5. → Plan shows: modify auto-scaling group
6. Review and approve PR
7. Merge to main
8. → terraform-apply workflow triggered
9. Click "Review deployments" button
10. Approve for production
11. → terraform apply runs (✓)
12. EKS nodes scale up
13. → drift-detection runs (✓ no drift)
14. → eks-validation confirms nodes healthy
15. ✅ COMPLETE
```

### Scenario 2: Drift Detected (Manual AWS Change)

```
1. Team member logs into AWS Console
2. Manually updates security group rule
3. Next drift detection (2 AM UTC)
4. → terraform-drift-detection detects drift
5. → Creates GitHub issue "Drift Detected"
6. → Sends Slack alert
7. Team reviews issue
8. Options:
   a) Destroy and re-apply via PR
   b) Import manual change to state
   c) Investigate and reverse manual change
9. Resolve and verify no drift next cycle
```

### Scenario 3: Emergency Rollback

```
1. Apply causes issues
2. Create branch: hotfix/rollback
3. Revert terraform changes
4. Create PR with rollback
5. → Validation passes
6. Merge to main
7. → Manual apply process
8. Approve for immediate deployment
9. Terraform applies rollback
10. ✅ System restored
```

---

## Metrics to Track

### Deployment Metrics
- Pull request to merge time: ___ minutes
- Merge to apply approval time: ___ minutes
- Apply execution time: 5-10 minutes
- Total deployment cycle time: ___ hours

### Reliability Metrics
- Successful PR validations: __%
- Successful applies: __%
- Drift detection false positives: __%
- EKS validation failures: __%

### Team Metrics
- Deployments per week: ___
- Manual approvals per week: ___
- Drift alerts per week: ___
- Rollbacks per month: ___

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [PIPELINE_SETUP.md](./PIPELINE_SETUP.md) | Complete setup instructions |
| [PIPELINE_CONFIG.md](./PIPELINE_CONFIG.md) | Configuration templates & reference |
| [PIPELINE_QUICKREF.md](./PIPELINE_QUICKREF.md) | Quick command reference |
| [IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md) | Step-by-step implementation guide |
| [main.tf](./main.tf) | EKS cluster Terraform code |
| [variables.tf](./variables.tf) | Terraform variables & defaults |

---

**Last Updated**: 2024
**Pipeline Version**: 1.0
**Status**: Ready for Implementation ✓

Start with [IMPLEMENTATION_CHECKLIST.md](./IMPLEMENTATION_CHECKLIST.md) to begin setup.
