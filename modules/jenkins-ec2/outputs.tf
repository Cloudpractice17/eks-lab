output "instance_id" {
  value = aws_instance.jenkins.id
}

output "private_ip" {
  description = "Register this as a target in the internal ALB's target group"
  value       = aws_instance.jenkins.private_ip
}

output "security_group_id" {
  description = "Pass this to other modules that need to allow traffic to Jenkins"
  value       = aws_security_group.jenkins.id
}
