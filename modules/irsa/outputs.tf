output "jenkins_role_arn" {
  description = "Annotate the Jenkins Kubernetes service account with this ARN to activate IRSA"
  value       = aws_iam_role.jenkins.arn
}

output "argocd_role_arn" {
  description = "Annotate the Argo CD server service account with this ARN"
  value       = aws_iam_role.argocd.arn
}
