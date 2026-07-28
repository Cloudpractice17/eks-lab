# WHY SSM Parameter Store instead of tfvars:
# terraform.tfvars is a file on disk that can be committed accidentally,
# passed around, or read by anyone with machine access. SSM stores
# secrets encrypted in AWS — Terraform reads them at apply time, they
# never touch your filesystem, and IAM controls who can read them.
#
# HOW to use this:
# 1. terraform apply creates the Parameter Store paths
# 2. You manually put the actual secret values via AWS Console or CLI
#    (see outputs for the exact paths)
# 3. Every other module that needs a secret reads it from SSM at
#    runtime — not from a variable file

resource "aws_ssm_parameter" "sonarqube_token" {
  name        = "/${var.name}/${var.environment}/sonarqube/token"
  description = "SonarQube authentication token for Jenkins pipeline"
  type        = "SecureString"
  value       = "PLACEHOLDER_REPLACE_AFTER_APPLY"
  # WHY PLACEHOLDER: Terraform creates the path and encryption config.
  # You replace the value manually after apply — this way the secret
  # never appears in your .tf files or state in plaintext.

  lifecycle {
    # WHY ignore_changes on value: once you set the real secret via CLI
    # or console, Terraform will not overwrite it on the next apply.
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "nexus_password" {
  name        = "/${var.name}/${var.environment}/nexus/admin-password"
  description = "Nexus admin password for artifact publishing"
  type        = "SecureString"
  value       = "PLACEHOLDER_REPLACE_AFTER_APPLY"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "github_token" {
  name        = "/${var.name}/${var.environment}/github/token"
  description = "GitHub token for Jenkins to push GitOps repo updates"
  type        = "SecureString"
  value       = "PLACEHOLDER_REPLACE_AFTER_APPLY"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "argocd_password" {
  name        = "/${var.name}/${var.environment}/argocd/admin-password"
  description = "Argo CD admin password"
  type        = "SecureString"
  value       = "PLACEHOLDER_REPLACE_AFTER_APPLY"
  lifecycle { ignore_changes = [value] }
}
