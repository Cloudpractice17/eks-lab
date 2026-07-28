variable "name" {
  description = "Prefix for resource names"
  type        = string
  default     = "eks-lab"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "Which public subnet to launch the bastion in — needs to be public so it has a route to the internet for SSH"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your public IP as a /32, e.g. \"203.0.113.5/32\" — NOT a range, and never 0.0.0.0/0. See GETTING-STARTED.md for the exact command to find your current IP."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && endswith(var.allowed_ssh_cidr, "/32")
    error_message = "allowed_ssh_cidr must be a single-address CIDR ending in /32 — a range or 0.0.0.0/0 defeats the purpose of this variable."
  }
}

variable "ssh_public_key_path" {
  description = "Local path to your SSH public key file, e.g. \"C:/Users/you/.ssh/bastion-key.pub\""
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
