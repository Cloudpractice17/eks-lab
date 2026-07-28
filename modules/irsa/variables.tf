variable "name"             { type = string }
variable "aws_region"       { type = string }
variable "aws_account_id"   { type = string }
variable "oidc_provider_arn" {
  description = "From eks module output — the ARN of the cluster's OIDC provider"
  type        = string
}
variable "oidc_issuer_url" {
  description = "From eks module output — without https://, used in IAM condition keys"
  type        = string
}
