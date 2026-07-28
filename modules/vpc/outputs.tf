output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Pass these to the EKS module — nodes must run in private subnets"
  value       = aws_subnet.private[*].id
}
