output "ecr_repository_urls" {
  description = "Paste these into Jenkinsfile.app as ECR_REPO values"
  value       = module.ecr.repository_urls
}

output "secret_paths" {
  description = "SSM paths to populate with real secrets after apply"
  value       = module.secrets.secret_paths
}

output "populate_commands" {
  description = "Run these PowerShell commands to set real secret values"
  value       = module.secrets.populate_commands
}

output "sns_topic_arn" {
  value = module.observability.sns_topic_arn
}

output "zone_id" {
  value = module.internal_dns.zone_id
}

output "record_fqdns" {
  value = module.internal_dns.record_fqdns
}

output "bastion_public_ip" {
  description = "SSH here — or use instance_id below with SSM as a fallback"
  value       = module.bastion.public_ip
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}

output "jenkins_private_ip" {
  description = "Jenkins is in a private subnet — reach the UI through the internal ALB, not directly"
  value       = module.jenkins.private_ip
}

output "jenkins_instance_id" {
  description = "Use this to SSH via the bastion: ssh -J ec2-user@<bastion_ip> ec2-user@<this>"
  value       = module.jenkins.instance_id
}

output "jenkins_iam_role_arn" {
  description = "The scoped role Jenkins uses to run terraform — useful for audit logs"
  value       = module.jenkins_iam.role_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "Save this — you'll need it when building IRSA roles next"
  value       = module.eks.oidc_provider_arn
}

# Gap 3 outputs — needed to populate k8s/irsa/service-accounts.yaml
output "jenkins_irsa_role_arn" {
  description = "Paste into k8s/irsa/service-accounts.yaml jenkins annotation"
  value       = module.irsa.jenkins_role_arn
}
output "argocd_irsa_role_arn" {
  description = "Paste into k8s/irsa/service-accounts.yaml argocd annotation"
  value       = module.irsa.argocd_role_arn
}
# Gap 1+2 outputs
output "eks_kms_key_arn" {
  value = module.eks.kms_key_arn
}
output "guardduty_detector_id" {
  value = module.eks.guardduty_detector_id
}
