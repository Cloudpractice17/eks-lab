output "role_arn" {
  description = "Add this as AWS_ROLE_ARN in GitHub repo secrets. GitHub Actions uses it to authenticate to AWS without any access keys."
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
