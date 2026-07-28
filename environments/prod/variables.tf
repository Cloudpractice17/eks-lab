variable "aws_region"         { type = string }
variable "project_name"       { type = string; default = "eks-lab" }
variable "state_bucket_name"  { type = string }
variable "allowed_ssh_cidr"   { type = string }
variable "ssh_public_key_path"{ type = string }
variable "zone_name"          { type = string; default = "eks.internal" }
variable "alert_email"        { type = string; default = "" }
variable "records"            { type = map(string); default = {} }
variable "ecr_repositories"   { type = list(string); default = ["myapp"] }

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]   # larger than dev
}
variable "node_desired_size" { type = number; default = 3 }
variable "node_min_size"     { type = number; default = 2 }
variable "node_max_size"     { type = number; default = 6 }
