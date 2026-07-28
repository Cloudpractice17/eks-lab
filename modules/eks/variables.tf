variable "name" {
  description = "Cluster name — also prefixes the IAM roles this module creates"
  type        = string
  default     = "eks-lab"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane"
  type        = string
  default     = "1.31"
}

variable "private_subnet_ids" {
  description = "From the vpc module's output — nodes run here"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "From the vpc module's output — the control plane's ENIs can use these too"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance type(s) for worker nodes. t3.medium is the practical minimum — smaller sizes struggle to run kubelet plus real workloads"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}
