# WHY this exists as its own module:
# Jenkins needs an IAM role to run terraform plan/apply. The wrong
# approach (what most tutorials do) is to give Jenkins the same admin
# key you used during setup. That means a misconfigured pipeline job,
# a leaked Jenkinsfile, or a compromised build can touch your entire
# AWS account.
#
# This module creates a scoped IAM role that:
# - Can only be assumed by the Jenkins EC2 instance (via its instance
#   profile ARN), not by any human or other service
# - Has exactly the permissions Terraform needs to manage your VPC,
#   EKS, bastion, Route 53, and S3 state — nothing else
# - Is attached as an instance profile so Jenkins assumes it
#   automatically, no access keys stored anywhere on disk

resource "aws_iam_role" "jenkins_terraform" {
  name = "${var.name}-jenkins-terraform-role"
  description = "Assumed by the Jenkins instance to run terraform plan/apply"

  # WHY this trust policy and not a broader one:
  # Only the specific Jenkins EC2 instance (identified by its instance
  # profile ARN) can assume this role. Not all EC2 instances, not all
  # IAM users — just Jenkins. If Jenkins is ever compromised, the blast
  # radius is limited to what this role can touch.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowJenkinsEC2ToAssume"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# --- S3: state bucket access only ---
# WHY scoped to the specific bucket:
# Terraform needs to read and write state. This allows exactly that,
# on the one bucket that holds your state — not every S3 bucket in
# your account.
resource "aws_iam_policy" "s3_state" {
  name = "${var.name}-jenkins-s3-state"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.state_bucket_name}",
          "arn:aws:s3:::${var.state_bucket_name}/*"
        ]
      }
    ]
  })
}

# --- EC2 / VPC permissions for vpc + bastion modules ---
resource "aws_iam_policy" "ec2_vpc" {
  name = "${var.name}-jenkins-ec2-vpc"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "VPCAndEC2"
      Effect = "Allow"
      Action = [
        "ec2:*"
      ]
      # WHY not resource-scoped here: EC2 Describe actions can't be
      # scoped to a specific resource — AWS requires * for those.
      # Create/Delete actions could be scoped but it would make the
      # policy unmanageably long for a learning project. A real
      # production hardening pass would split Describe from Create/Delete
      # and add resource-level conditions on the latter.
      Resource = "*"
    }]
  })
}

# --- EKS permissions ---
resource "aws_iam_policy" "eks" {
  name = "${var.name}-jenkins-eks"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EKSManagement"
      Effect = "Allow"
      Action = [
        "eks:*"
      ]
      Resource = "*"
    }]
  })
}

# --- IAM permissions (for creating the node role, OIDC provider etc) ---
# WHY PassRole is in here:
# Terraform creates IAM roles and then assigns them to resources
# (e.g. attaches the node role to the node group). AWS requires
# iam:PassRole permission for that assignment step. Without it,
# terraform apply fails even if it can create the role.
resource "aws_iam_policy" "iam" {
  name = "${var.name}-jenkins-iam"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:ListRoles",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Route 53 permissions ---
resource "aws_iam_policy" "route53" {
  name = "${var.name}-jenkins-route53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "Route53Management"
      Effect = "Allow"
      Action = [
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:ListHostedZonesByName",
        "route53:ChangeResourceRecordSets",
        "route53:GetChange",
        "route53:ListResourceRecordSets",
        "route53:AssociateVPCWithHostedZone",
        "route53:DisassociateVPCFromHostedZone"
      ]
      Resource = "*"
    }]
  })
}

# Attach all policies to the role
resource "aws_iam_role_policy_attachment" "s3_state" {
  role       = aws_iam_role.jenkins_terraform.name
  policy_arn = aws_iam_policy.s3_state.arn
}
resource "aws_iam_role_policy_attachment" "ec2_vpc" {
  role       = aws_iam_role.jenkins_terraform.name
  policy_arn = aws_iam_policy.ec2_vpc.arn
}
resource "aws_iam_role_policy_attachment" "eks" {
  role       = aws_iam_role.jenkins_terraform.name
  policy_arn = aws_iam_policy.eks.arn
}
resource "aws_iam_role_policy_attachment" "iam" {
  role       = aws_iam_role.jenkins_terraform.name
  policy_arn = aws_iam_policy.iam.arn
}
resource "aws_iam_role_policy_attachment" "route53" {
  role       = aws_iam_role.jenkins_terraform.name
  policy_arn = aws_iam_policy.route53.arn
}

# Instance profile wraps the role so EC2 (Jenkins) can assume it
resource "aws_iam_instance_profile" "jenkins_terraform" {
  name = "${var.name}-jenkins-terraform-profile"
  role = aws_iam_role.jenkins_terraform.name
}
