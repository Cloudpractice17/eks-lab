variable "aws_region" {
  description = "Region to create resources in"
  type        = string
  default     = "ap-south-1"
}
variable "project_name" {
  type    = string
  default = "eks-lab"
}
variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
}
variable "github_org" {
  description = "Your GitHub username or org — e.g. sarandevops"
  type        = string
}
variable "github_repo" {
  description = "Your repository name — e.g. eks-lab"
  type        = string
}
