# WHY IRSA instead of broad node-level IAM:
# Without IRSA, every pod on a node inherits the node's IAM role.
# If Jenkins needs ECR push access, every other pod on that node —
# your app, SonarQube, a compromised dependency — also gets ECR push
# access. With IRSA, only the Jenkins pod's specific service account
# can assume the Jenkins IAM role. Compromise one pod, you get that
# pod's permissions only.
#
# HOW IT WORKS:
# 1. Pod starts with a Kubernetes service account
# 2. EKS injects a short-lived OIDC token into the pod
# 3. AWS SDK in the pod exchanges the OIDC token for temporary IAM
#    credentials via sts:AssumeRoleWithWebIdentity
# 4. The IAM role's trust policy only allows assumption from the
#    specific namespace + service account combination

# ── Jenkins IRSA role ───────────────────────────────────────────────

resource "aws_iam_role" "jenkins" {
  name        = "${var.name}-jenkins-irsa"
  description = "Assumed only by the Jenkins pod via IRSA — not by any other pod or node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # WHY both conditions:
          # aud restricts to AWS STS — prevents other OIDC consumers
          # from using this token. sub restricts to the exact
          # namespace:serviceaccount pair — only Jenkins in the jenkins
          # namespace can assume this role, not Jenkins in default.
          "${var.oidc_issuer_url}:aud" = "sts.amazonaws.com"
          "${var.oidc_issuer_url}:sub" = "system:serviceaccount:jenkins:jenkins"
        }
      }
    }]
  })
}

# WHY ECR permissions scoped to your account only:
# Jenkins needs to push images it builds. This allows push/pull to ECR
# repos in your account only — not to any ECR repo in AWS.
resource "aws_iam_policy" "jenkins_ecr" {
  name = "${var.name}-jenkins-ecr"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        # WHY *: GetAuthorizationToken is a global call, not per-repo
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        # Scoped to your account's repos only, not all ECR globally
        Resource = "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/*"
      }
    ]
  })
}

# Jenkins also needs SSM read to fetch secrets at build time
resource "aws_iam_policy" "jenkins_ssm" {
  name = "${var.name}-jenkins-ssm"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SSMReadSecrets"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      # Scoped to only the /eks-lab/ path — not all SSM parameters
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.name}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins_ecr.arn
}
resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins_ssm.arn
}

# ── Argo CD IRSA role ───────────────────────────────────────────────

resource "aws_iam_role" "argocd" {
  name        = "${var.name}-argocd-irsa"
  description = "Assumed only by the Argo CD server pod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_url}:aud" = "sts.amazonaws.com"
          # Argo CD server runs in the argocd namespace
          "${var.oidc_issuer_url}:sub" = "system:serviceaccount:argocd:argocd-server"
        }
      }
    }]
  })
}

# WHY Argo CD needs ECR read: it pulls manifests that reference ECR image
# URIs and needs to validate them. Read-only — never push.
resource "aws_iam_policy" "argocd_ecr_read" {
  name = "${var.name}-argocd-ecr-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "argocd_ecr" {
  role       = aws_iam_role.argocd.name
  policy_arn = aws_iam_policy.argocd_ecr_read.arn
}
