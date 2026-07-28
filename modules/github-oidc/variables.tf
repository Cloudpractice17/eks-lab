variable "name" {
  type    = string
  default = "eks-lab"
}

variable "github_org" {
  description = "Your GitHub username or organisation name — e.g. 'sarandevops'"
  type        = string
}

variable "github_repo" {
  description = "Your repository name — e.g. 'eks-lab'"
  type        = string
}

variable "state_bucket_name" {
  description = "S3 state bucket name — IAM policy is scoped to this bucket only"
  type        = string
}
