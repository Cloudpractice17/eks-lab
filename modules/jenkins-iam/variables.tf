variable "name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "eks-lab"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state — the IAM policy is scoped to exactly this bucket"
  type        = string
}
