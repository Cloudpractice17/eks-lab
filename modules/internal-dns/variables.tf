variable "zone_name" {
  description = "Internal DNS zone name, e.g. eks.internal"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the zone is scoped to — the zone only resolves inside this VPC"
  type        = string
}

variable "aws_region" {
  description = "Region the VPC lives in"
  type        = string
}

variable "records" {
  description = "Map of short app name to its load balancer name. Each entry becomes <key>.<zone_name>, e.g. { jenkins = \"k8s-default-jenkins\" } -> jenkins.eks.internal"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the hosted zone"
  type        = map(string)
  default     = {}
}
