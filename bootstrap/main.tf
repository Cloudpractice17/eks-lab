terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
  # NO remote backend — this creates the bucket everything else uses.
  # Run once with local state.
}

provider "aws" { region = var.aws_region }

# ── S3 state bucket ──────────────────────────────────────────────────
resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name
  tags   = { ManagedBy = "terraform", Purpose = "terraform-remote-state" }
}
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── GitHub OIDC role ─────────────────────────────────────────────────
module "github_oidc" {
  source            = "../modules/github-oidc"
  name              = var.project_name
  github_org        = var.github_org
  github_repo       = var.github_repo
  state_bucket_name = var.state_bucket_name
}
