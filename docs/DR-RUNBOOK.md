# Disaster Recovery Runbook

## Scenario 1 — Terraform state is corrupted or accidentally deleted

### Signs
- `terraform plan` fails with "state file not found" or "error reading state"
- S3 bucket shows the state file is missing or zero bytes

### Recovery
S3 versioning is enabled on the state bucket (created by bootstrap).
Every apply creates a new version. Recovery is:

```
# List all versions of the state file
aws s3api list-object-versions \
  --bucket YOUR-STATE-BUCKET \
  --prefix eks-lab/dev/terraform.tfstate

# Restore a previous version by copying it back
aws s3api copy-object \
  --bucket YOUR-STATE-BUCKET \
  --copy-source YOUR-STATE-BUCKET/eks-lab/dev/terraform.tfstate?versionId=VERSIONID \
  --key eks-lab/dev/terraform.tfstate
```

After restoring, run `terraform plan` to verify state matches reality.
If resources exist in AWS but not in state, use `terraform import`
to re-register them.

---

## Scenario 2 — EKS cluster is accidentally destroyed

### Recovery time estimate: 20-30 minutes

```
cd environments/dev
terraform apply
aws eks update-kubeconfig --name eks-lab --region YOUR_REGION
kubectl apply -f ../../modules/argocd/applications.yaml
```

Argo CD will re-sync all apps from the GitOps repo automatically.
No application data is lost — the app is stateless. If it had
a database, the RDS restore procedure would go here.

---

## Scenario 3 — Jenkins instance is lost

### Recovery time estimate: 15 minutes (instance rebuilds itself)

```
# Terminate the broken instance
aws ec2 terminate-instances --instance-ids INSTANCE_ID

# Terraform replaces it on next apply
cd environments/dev
terraform apply

# Jenkins re-installs itself from user_data automatically.
# After ~3 minutes, retrieve the new initial admin password:
aws ssm send-command \
  --instance-ids NEW_INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cat /var/lib/jenkins/secrets/initialAdminPassword"]'
```

Pipeline jobs are stored in the Jenkins home directory (EBS volume).
If that volume is also lost, re-create jobs from the Jenkinsfile in
the repo — the Jenkinsfile is the source of truth, not the Jenkins UI.

---

## Scenario 4 — Secrets are lost from SSM

All secret values are in SSM Parameter Store, NOT in the repo.
If they are deleted, re-run `terraform apply` to re-create the paths,
then re-populate using the `populate_commands` output:

```
terraform output populate_commands
# Copy and run the aws ssm put-parameter commands it prints
```

---

## Scenario 5 — Bad deployment reaches prod

### Immediate rollback (< 2 minutes)

```
# Find the previous good image tag from ECR
aws ecr describe-images \
  --repository-name eks-lab/myapp \
  --query 'sort_by(imageDetails, &imagePushedAt)[-2].imageTags[0]' \
  --output text

# Update the GitOps prod manifest manually
cd gitops-repo
sed -i 's|image: .*|image: ACCOUNT.dkr.ecr.REGION.amazonaws.com/eks-lab/myapp:PREV_TAG|g' \
  prod/manifests/deployment.yaml
git commit -am "hotfix: rollback to PREV_TAG"
git push

# Sync Argo CD
argocd app sync myapp-prod --server ARGOCD_URL --auth-token TOKEN
```

### Verify rollback
```
kubectl rollout status deployment/myapp -n myapp-prod
kubectl get pods -n myapp-prod
```
