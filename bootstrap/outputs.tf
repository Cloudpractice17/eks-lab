output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}
output "github_actions_role_arn" {
  description = "ADD THIS to GitHub repo secrets as AWS_ROLE_ARN"
  value       = module.github_oidc.role_arn
}
