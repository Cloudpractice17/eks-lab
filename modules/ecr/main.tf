# WHY ECR over Docker Hub:
# ECR lives inside your AWS account, so your EKS nodes pull images
# over the private AWS network — no internet hop, no Docker Hub rate
# limits, and IAM controls who can push or pull.

resource "aws_ecr_repository" "app" {
  for_each = toset(var.repositories)

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  # WHY IMMUTABLE tags: once you push myapp:1.0.3, nobody can
  # overwrite it. This means your deployment history is auditable —
  # you can always roll back to an exact image that you know hasn't
  # changed under you.

  image_scanning_configuration {
    # WHY scan_on_push: every image gets a CVE scan the moment it
    # lands in ECR. Jenkins reads this result in the pipeline and
    # fails the build if HIGH or CRITICAL vulnerabilities are found —
    # before anything gets deployed.
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.name}/${each.key}" }
}

# WHY a lifecycle policy:
# Without this, every build pushes a new image tag and they pile up
# forever. At ~50MB–500MB each, that costs real money. This keeps
# the last 30 tagged images and deletes untagged (intermediate) images
# after 1 day.
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}
