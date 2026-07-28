variable "aws_region" {
  description = "AWS region your EKS cluster and VPC live in"
  type        = string
}

variable "project_name" {
  description = "Short name used to prefix every resource — VPC, EKS cluster, IAM roles"
  type        = string
  default     = "eks-lab"
}

variable "node_instance_types" {
  description = "EC2 instance type(s) for EKS worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "How many worker nodes to run"
  type        = number
  default     = 2
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket created by bootstrap — the Jenkins IAM policy is scoped to exactly this bucket"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your public IP as a /32 — see GETTING-STARTED.md for how to find it. Never set this to 0.0.0.0/0"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Local path to your SSH public key file"
  type        = string
}

variable "ecr_repositories" {
  description = "Image repo names to create in ECR"
  type        = list(string)
  default     = ["myapp"]
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "node_min_size" { type = number; default = 1 }
variable "node_max_size" { type = number; default = 3 }

variable "zone_name" {
  description = "Internal DNS zone name"
  type        = string
  default     = "eks.internal"
}

variable "records" {
  description = "Map of app name to load balancer name — add one entry per service you want an internal DNS name for"
  type        = map(string)
  default     = {}
}

# Gaps 1-3 require aws_region to be accessible at root level
# (already defined in most environments but ensure it is present)
