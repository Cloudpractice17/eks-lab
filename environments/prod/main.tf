terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # WHY a different key than dev:
  # prod state is completely separate from dev state. A terraform apply
  # in environments/dev cannot touch prod resources, and vice versa.
  # The only shared resource is the state bucket itself (created by bootstrap).
  backend "s3" {
    bucket       = "REPLACE-ME-your-terraform-state-bucket"
    key          = "eks-lab/prod/terraform.tfstate"
    region       = "REPLACE-ME-your-aws-region"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = "eks-lab"
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"
  name   = "${var.project_name}-prod"
}

module "eks" {
  source = "../../modules/eks"

  name                = "${var.project_name}-prod"
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  # WHY larger nodes in prod: prod handles real traffic. t3.medium is
  # the dev minimum; prod starts at t3.large to leave headroom.
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

module "bastion" {
  source = "../../modules/bastion"

  name                = "${var.project_name}-prod"
  vpc_id              = module.vpc.vpc_id
  public_subnet_id    = module.vpc.public_subnet_ids[0]
  allowed_ssh_cidr    = var.allowed_ssh_cidr
  ssh_public_key_path = var.ssh_public_key_path
}

module "jenkins_iam" {
  source            = "../../modules/jenkins-iam"
  name              = "${var.project_name}-prod"
  state_bucket_name = var.state_bucket_name
}

module "jenkins" {
  source = "../../modules/jenkins-ec2"

  name                      = "${var.project_name}-prod"
  vpc_id                    = module.vpc.vpc_id
  private_subnet_id         = module.vpc.private_subnet_ids[0]
  key_name                  = module.bastion.key_name
  iam_instance_profile_name = module.jenkins_iam.instance_profile_name
  alb_security_group_id     = module.bastion.security_group_id
  bastion_security_group_id = module.bastion.security_group_id
  instance_type             = "t3.large"
}

module "ecr" {
  source       = "../../modules/ecr"
  name         = var.project_name
  repositories = var.ecr_repositories
}

module "secrets" {
  source      = "../../modules/secrets"
  name        = var.project_name
  environment = "prod"
}

module "observability" {
  source = "../../modules/observability"

  name                = var.project_name
  environment         = "prod"
  eks_cluster_name    = module.eks.cluster_name
  jenkins_instance_id = module.jenkins.instance_id
  alert_email         = var.alert_email
}

module "internal_dns" {
  source = "../../modules/internal-dns"

  zone_name  = var.zone_name
  vpc_id     = module.vpc.vpc_id
  aws_region = var.aws_region
  records    = var.records

  tags = { Environment = "prod" }
}

module "irsa" {
  source = "../../modules/irsa"

  name              = "${var.project_name}-prod"
  aws_region        = var.aws_region
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = trimprefix(module.eks.oidc_issuer_url, "https://")
}

data "aws_caller_identity" "current" {}
