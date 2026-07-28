output "public_ip" {
  description = "Stable public IP (from the Elastic IP) — use this in PuTTY/ssh, and it won't change on restart"
  value       = aws_eip.bastion.public_ip
}

output "instance_id" {
  description = "Needed for the SSM fallback: aws ssm start-session --target <this>"
  value       = aws_instance.bastion.id
}

output "key_name" {
  description = "EC2 key pair name — Jenkins reuses the same key so you SSH in with one key file"
  value       = aws_key_pair.bastion.key_name
}

output "security_group_id" {
  description = "Passed to Jenkins so only the bastion can SSH into it"
  value       = aws_security_group.bastion.id
}
