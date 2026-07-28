# WHY IAM roles here: EKS itself needs permission to manage AWS resources
# on your behalf (the "cluster role"), and separately, each worker node
# needs its own permissions to join the cluster and pull images (the
# "node role"). These are two different identities doing two different
# jobs.

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── GAP 2: KMS key for envelope encryption of Kubernetes secrets ───────
# WHY envelope encryption:
# By default EKS encrypts the underlying EBS volume (storage-level).
# But anyone with API server access can still read Kubernetes Secret
# values in plaintext. Envelope encryption adds a second layer — secrets
# are encrypted with a data key (DEK), and the DEK is encrypted with
# this KMS customer-managed key (CMK). AWS Security Hub control EKS.3
# checks for this. Without it, a compromised kubeconfig means an attacker
# can read every secret in the cluster.
resource "aws_kms_key" "eks_secrets" {
  description             = "EKS secrets envelope encryption for ${var.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true   # WHY: rotate annually without disruption

  tags = { Name = "${var.name}-eks-secrets-key" }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)

    # ── GAP 1: Private API endpoint ──────────────────────────────────
    # WHY endpoint_public_access = false:
    # By default EKS creates a public API server endpoint — any IP on
    # the internet can attempt to authenticate against your cluster.
    # Setting this to false means the API server is only reachable from
    # inside the VPC. kubectl from your Jump Server still works because
    # the Jump Server is inside the VPC. kubectl from your laptop no
    # longer works directly — you must go through the Jump Server or
    # SSM port-forward.
    endpoint_public_access  = false
    endpoint_private_access = true
  }

  # ── GAP 2: Enable envelope encryption ──────────────────────────────
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  # ── GAP 6: Control plane audit logging ────────────────────────────
  # WHY these four log types:
  # audit        — every kubectl command, every API call — required for SOC 2
  # authenticator— IAM authentication events — who logged in and when
  # api          — API server errors and slow requests
  # controllerManager — workload scheduling decisions
  # scheduler is omitted — low signal, high volume, adds cost
  enabled_cluster_log_types = ["audit", "authenticator", "api", "controllerManager"]

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# --- Node group ---

resource "aws_iam_role" "node" {
  name = "${var.name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# --- OIDC provider (prerequisite for IRSA) ---

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

# ── GAP 6: CloudWatch log group for cluster logs ──────────────────────
# WHY explicit retention: without this, CloudWatch keeps logs forever
# and cost grows unbounded. 90 days is enough for security investigation
# while keeping the bill predictable.
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 90

  # WHY KMS encryption on log group:
  # Audit logs may contain sensitive values from API request bodies.
  # Encrypting the log group with the same KMS key closes that gap.
  kms_key_id = aws_kms_key.eks_secrets.arn
}

# ── GAP 7: GuardDuty EKS protection ──────────────────────────────────
# WHY GuardDuty over rolling your own threat detection:
# GuardDuty monitors the Kubernetes audit log for 30+ threat patterns
# (cryptomining, credential theft, privilege escalation, lateral
# movement) using AWS threat intelligence. ~$2-5/month per cluster.
# Turning it on takes two resources — there is no excuse not to.
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}
