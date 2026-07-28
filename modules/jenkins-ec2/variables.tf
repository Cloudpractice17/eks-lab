variable "name" {
  type    = string
  default = "eks-lab"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_id" {
  description = "Jenkins lives in a private subnet — no public IP"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name — use the same one as the bastion so you SSH in with the same key"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "From the jenkins-iam module output — gives Jenkins the scoped Terraform role"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group of the internal ALB — only the ALB can reach Jenkins on port 8080"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security group of the bastion — only the bastion can SSH into Jenkins"
  type        = string
}

variable "instance_type" {
  description = "t3.medium is the minimum — Jenkins with a few concurrent builds needs at least 2 vCPU / 4GB"
  type        = string
  default     = "t3.medium"
}

variable "terraform_version" {
  description = "Must match the version in your .tf files' required_version constraint"
  type        = string
  default     = "1.10.0"
}

variable "kubectl_version" {
  description = "Should match your EKS cluster's Kubernetes version"
  type        = string
  default     = "1.31.0"
}
