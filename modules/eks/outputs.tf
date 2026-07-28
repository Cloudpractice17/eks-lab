output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "oidc_provider_arn" {
  description = "Needed by any future IRSA role — pass this in when you build Jenkins/Argo CD's scoped IAM roles"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "kms_key_arn" {
  description = "KMS key used for secrets envelope encryption — also used for CloudWatch log group encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}
