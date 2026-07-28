terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # WHY tls is here even though you never call it directly: the eks
    # module uses it internally (data "tls_certificate") to set up the
    # OIDC provider. Terraform requires every provider used anywhere in
    # the module tree to be declared in the root's required_providers.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # use_lockfile = native S3 state locking, available Terraform 1.10+.
  # Replaces the older pattern of a separate DynamoDB table for locking —
  # one less resource to manage. If you're on an older Terraform version,
  # drop use_lockfile and add a DynamoDB table with a "LockID" string key
  # instead, then reference it here as dynamodb_table = "your-table-name".
  backend "s3" {
    bucket       = "REPLACE-ME-your-terraform-state-bucket"
    key          = "route53/dev/terraform.tfstate"
    region       = "REPLACE-ME-your-aws-region"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # WHY default_tags: every resource created by this config gets these
  # tags automatically — no risk of a resource slipping through untagged
  # because someone forgot to add a tags block.
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "eks-internal-dns"
      ManagedBy   = "terraform"
    }
  }
}

# WHY this order: vpc has no dependencies, eks depends on vpc's subnets,
# and internal_dns depends on vpc's ID. Terraform figures out the actual
# apply order from these references — you don't have to sequence it
# yourself, but reading top-to-bottom in this order matches how it builds.

module "vpc" {
  source = "../../modules/vpc"
  name   = var.project_name
}

module "eks" {
  source = "../../modules/eks"

  name                = var.project_name
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
}

module "bastion" {
  source = "../../modules/bastion"

  name                = var.project_name
  vpc_id              = module.vpc.vpc_id
  public_subnet_id    = module.vpc.public_subnet_ids[0]
  allowed_ssh_cidr    = var.allowed_ssh_cidr
  ssh_public_key_path = var.ssh_public_key_path
}

# WHY jenkins-iam comes before jenkins-ec2:
# The EC2 module takes the instance profile name as an input.
# The profile doesn't exist until the IAM module creates it.
# Terraform will infer this ordering from the reference, but keeping
# the code in dependency order makes it easier to read.

module "jenkins_iam" {
  source            = "../../modules/jenkins-iam"
  name              = var.project_name
  state_bucket_name = var.state_bucket_name
}

module "jenkins" {
  source = "../../modules/jenkins-ec2"

  name                      = var.project_name
  vpc_id                    = module.vpc.vpc_id
  private_subnet_id         = module.vpc.private_subnet_ids[0]
  key_name                  = module.bastion.key_name
  iam_instance_profile_name = module.jenkins_iam.instance_profile_name
  alb_security_group_id     = module.bastion.security_group_id   # reuse bastion ALB SG
  bastion_security_group_id = module.bastion.security_group_id
}

module "ecr" {
  source       = "../../modules/ecr"
  name         = var.project_name
  repositories = var.ecr_repositories
}

module "secrets" {
  source      = "../../modules/secrets"
  name        = var.project_name
  environment = "dev"
}

module "observability" {
  source = "../../modules/observability"

  name                = var.project_name
  environment         = "dev"
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

  tags = {
    Environment = "dev"
  }
}

# ── GAP 3: IRSA — scoped IAM roles per pod ──────────────────────────
# Jenkins and Argo CD get their own IAM roles with only the permissions
# they need. Replaces the broad node-level IAM permissions they
# previously inherited.
module "irsa" {
  source = "../../modules/irsa"

  name              = var.project_name
  aws_region        = var.aws_region
  aws_account_id    = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = trimprefix(module.eks.oidc_issuer_url, "https://")
}

data "aws_caller_identity" "current" {}
