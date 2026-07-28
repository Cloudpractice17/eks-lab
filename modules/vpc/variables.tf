variable "name" {
  description = "Prefix used to name every resource this module creates, e.g. \"eks-lab\""
  type        = string
  default     = "eks-lab"
}

variable "vpc_cidr" {
  description = "IP range for the whole VPC. /16 gives you 65,536 addresses — far more than you need, but it's the standard starting size"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "One CIDR per public subnet (one per AZ). Must be inside vpc_cidr and not overlap each other or the private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "One CIDR per private subnet (one per AZ) — this is where your EKS nodes live"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "nat_instance_type" {
  description = "Instance size for the NAT instance. t3.micro is enough for light traffic like a learning cluster"
  type        = string
  default     = "t3.micro"
}
