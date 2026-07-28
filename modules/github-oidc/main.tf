# WHY OIDC instead of access keys:
# The old way: create an IAM user, generate access keys, store them
# as GitHub secrets. Problem: keys are long-lived, can be leaked,
# need rotating, and if your repo is public anyone who finds them
# owns your AWS account.
#
# The OIDC way: GitHub proves its identity to AWS using a signed
# JWT token. AWS verifies the token, issues a short-lived credential
# (expires in 1 hour), and the job uses it. No secret to store,
# no key to rotate, no leak risk.
#
# HOW IT WORKS:
# 1. This module creates an OIDC provider that trusts GitHub's token issuer
# 2. It creates an IAM role that GitHub Actions can assume
# 3. The role only allows assumption from YOUR specific repo
#    (not any GitHub Actions run anywhere in the world)
# 4. The workflow uses aws-actions/configure-aws-credentials to get
#    the token and assume the role automatically

data "aws_caller_identity" "current" {}

# Register GitHub's OIDC provider with AWS
# This tells AWS: "I trust JWT tokens signed by GitHub"
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint — this is a fixed value from GitHub's
  # certificate chain. It tells AWS which TLS certificate to trust.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM role that GitHub Actions assumes during workflow runs
resource "aws_iam_role" "github_actions" {
  name = "${var.name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # WHY this condition:
            # Without it, ANY GitHub Actions workflow anywhere could
            # assume this role. This locks it to YOUR specific repo
            # and only the main branch (for apply) or any branch
            # (for plan/validate on PRs).
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Format: repo:ORG/REPO:ref:refs/heads/BRANCH
            # The * allows any branch to run plan/validate
            # Apply is further restricted by the GitHub Environment gate
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

# Attach the same scoped policies as the Jenkins IAM role
# (same permissions needed — both run terraform apply)
resource "aws_iam_role_policy_attachment" "ec2_vpc" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "eks" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_worker" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "iam_full" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "route53" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

# S3 access scoped to the state bucket only
resource "aws_iam_policy" "s3_state" {
  name = "${var.name}-github-actions-s3-state"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.state_bucket_name}",
        "arn:aws:s3:::${var.state_bucket_name}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_state" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.s3_state.arn
}
