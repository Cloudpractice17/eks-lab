output "secret_paths" {
  description = "After terraform apply, run the commands below to set the real secret values. Never put real values in tfvars."
  value = {
    sonarqube_token  = aws_ssm_parameter.sonarqube_token.name
    nexus_password   = aws_ssm_parameter.nexus_password.name
    github_token     = aws_ssm_parameter.github_token.name
    argocd_password  = aws_ssm_parameter.argocd_password.name
  }
}

output "populate_commands" {
  description = "Run these in PowerShell after apply to set real secret values"
  value = <<-EOT
    aws ssm put-parameter --name "${aws_ssm_parameter.sonarqube_token.name}" --value "YOUR_SONAR_TOKEN" --type SecureString --overwrite
    aws ssm put-parameter --name "${aws_ssm_parameter.nexus_password.name}" --value "YOUR_NEXUS_PASSWORD" --type SecureString --overwrite
    aws ssm put-parameter --name "${aws_ssm_parameter.github_token.name}" --value "YOUR_GITHUB_TOKEN" --type SecureString --overwrite
    aws ssm put-parameter --name "${aws_ssm_parameter.argocd_password.name}" --value "YOUR_ARGOCD_PASSWORD" --type SecureString --overwrite
  EOT
}
