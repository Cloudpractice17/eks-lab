variable "name" { type = string }
variable "environment" { type = string }
variable "eks_cluster_name" { type = string }
variable "jenkins_instance_id" { type = string }
variable "alert_email" {
  description = "Email address to receive alarm notifications. Leave empty to skip email subscription."
  type        = string
  default     = ""
}
