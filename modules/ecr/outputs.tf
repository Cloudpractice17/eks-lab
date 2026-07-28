output "repository_urls" {
  description = "Map of repo name to full ECR URL — used in Jenkinsfile docker push commands"
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}
