output "instance_profile_name" {
  description = "Attach this to the Jenkins EC2 instance — it gives Jenkins the Terraform role automatically, no access keys needed"
  value       = aws_iam_instance_profile.jenkins_terraform.name
}

output "role_arn" {
  description = "The ARN of the scoped Terraform role — useful for audit logs and for setting up cross-account access later"
  value       = aws_iam_role.jenkins_terraform.arn
}
