# Closing the Scorecard Gaps — Exact Apply Order

Every change below is a git push that triggers GitHub Actions.
No terraform apply from your laptop or CloudShell.

---

## Changes made to existing files

### modules/eks/main.tf  (Gaps 1, 2, 6, 7)
- endpoint_public_access  = false  ← Gap 1: private API endpoint
- endpoint_private_access = true
- encryption_config (KMS)          ← Gap 2: envelope encryption
- enabled_cluster_log_types        ← Gap 6: audit logging
- aws_guardduty_detector           ← Gap 7: threat detection

### environments/dev/main.tf  (Gap 3)
- module "irsa" added              ← Gap 3: scoped IAM per pod

### environments/prod/main.tf  (Gap 3)
- module "irsa" added

## New files added
- modules/irsa/                    ← Gap 3: Jenkins + Argo CD IRSA roles
- k8s/irsa/service-accounts.yaml  ← Gap 3: Kubernetes SA annotations
- k8s/network-policies/policies.yaml ← Gap 4: default-deny + allow rules
- k8s/pod-security/namespaces.yaml   ← Gap 5: Pod Security Standards
- k8s/rbac/hardening.yaml            ← Gap 4 (RBAC): disable automount

---

## Step 1 — Push Terraform changes (GitHub Actions applies Gaps 1, 2, 3, 6, 7)

```bash
git add modules/eks/main.tf
git add modules/eks/outputs.tf
git add modules/irsa/
git add environments/dev/main.tf
git add environments/dev/outputs.tf
git add environments/prod/main.tf
git commit -m "sec: close scorecard gaps 1,2,3,6,7 — private endpoint, KMS, IRSA, audit logs, GuardDuty"
git push origin main
```

Open a PR → review the plan carefully — you will see:
- aws_eks_cluster changes (endpoint_public_access, encryption_config, logging)
- aws_kms_key created
- aws_guardduty_detector created
- aws_iam_role.jenkins + aws_iam_role.argocd created
- aws_cloudwatch_log_group.eks_cluster created

Merge → approve the apply in GitHub Actions.

⚠️  IMPORTANT: After this apply your laptop can no longer reach the EKS
API directly (that is the point of Gap 1). All kubectl commands must run
from the Jump Server via PuTTY. Verify on the Jump Server:
```bash
kubectl get nodes
# Must still work from Jump Server — it is inside the VPC
```

---

## Step 2 — Fill in the IRSA role ARNs and apply Kubernetes manifests

After GitHub Actions completes, get the role ARNs from the workflow output:

```bash
# In GitHub Actions "Show outputs" step, copy:
# jenkins_irsa_role_arn = arn:aws:iam::ACCOUNT:role/eks-lab-jenkins-irsa
# argocd_irsa_role_arn  = arn:aws:iam::ACCOUNT:role/eks-lab-argocd-irsa
```

Edit k8s/irsa/service-accounts.yaml — replace both REPLACE-ME placeholders
with the real ARNs. Then from your Jump Server:

```bash
# From the Jump Server:
kubectl apply -f k8s/irsa/service-accounts.yaml

# Restart Jenkins and Argo CD pods so they pick up the new service account:
kubectl rollout restart deployment/jenkins -n jenkins
kubectl rollout restart deployment/argocd-server -n argocd

# Verify IRSA is working — Jenkins pod should have AWS credentials:
kubectl exec -n jenkins deploy/jenkins -- aws sts get-caller-identity
# Expected: shows jenkins-irsa role ARN, NOT the node role
```

---

## Step 3 — Apply namespace labels (Gaps 4, 5) and RBAC hardening

```bash
# From the Jump Server:

# Gap 5 — Pod Security Standards (namespace labels)
kubectl apply -f k8s/pod-security/namespaces.yaml

# Check for any existing violations (warn mode shows them without blocking):
kubectl get events --field-selector reason=FailedCreate -A

# Gap 4 — Network policies (default-deny + allow rules)
kubectl apply -f k8s/network-policies/policies.yaml

# Verify policies applied in each namespace:
kubectl get networkpolicy -n jenkins
kubectl get networkpolicy -n argocd
kubectl get networkpolicy -n monitoring
kubectl get networkpolicy -n myapp-dev

# RBAC hardening
kubectl apply -f k8s/rbac/hardening.yaml

# Test that your app still works after network policies:
kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://myapp.eks.internal/
# Expected: still returns 200 (allowed traffic path is in the policy)
```

---

## Step 4 — Verify all 7 gaps are closed

```bash
# Gap 1 — Private API endpoint
aws eks describe-cluster --name eks-lab --region ap-south-1 \
  --query "cluster.resourcesVpcConfig.{pub:endpointPublicAccess,priv:endpointPrivateAccess}"
# Expected: {"pub": false, "priv": true}

# Gap 2 — KMS encryption
aws eks describe-cluster --name eks-lab --region ap-south-1 \
  --query "cluster.encryptionConfig"
# Expected: shows resources:["secrets"] and a KMS key ARN

# Gap 3 — IRSA (Jenkins pod uses scoped role, not node role)
kubectl exec -n jenkins deploy/jenkins -- aws sts get-caller-identity \
  --query "Arn" --output text
# Expected: contains "jenkins-irsa", NOT the node instance profile

# Gap 4 — Network policies exist
kubectl get networkpolicy -A | grep default-deny
# Expected: shows default-deny in jenkins, argocd, monitoring, myapp-dev, myapp-prod

# Gap 5 — Pod Security Standards labels on namespaces
kubectl get ns myapp-dev --show-labels | grep pod-security
# Expected: enforce=restricted

# Gap 6 — Audit logging enabled
aws eks describe-cluster --name eks-lab --region ap-south-1 \
  --query "cluster.logging.clusterLogging[?enabled==\`true\`].types"
# Expected: [["audit","authenticator","api","controllerManager"]]

# Gap 7 — GuardDuty EKS protection active
aws guardduty list-detectors --region ap-south-1
# Expected: returns a detector ID
aws guardduty get-detector --detector-id <ID> --region ap-south-1 \
  --query "Features[?Name=='KUBERNETES_AUDIT_LOGS'].Status"
# Expected: ["ENABLED"]
```

After all 7 verify commands pass, the project is at ~85-90% production standard.
