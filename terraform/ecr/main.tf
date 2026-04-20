# ECR repositories for Lambda container images.
# Deploy this stack BEFORE environmental stack, and push at least one image per
# repo before the environmental stack creates the Lambda functions.

locals {
  repos = toset(["log-enricher", "dashboard-generator"])
}

resource "aws_ecr_repository" "lambda" {
  for_each = local.repos

  name                 = "${var.project_prefix}-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_prefix}-${each.key}"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "lambda" {
  for_each = aws_ecr_repository.lambda

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

output "log_enricher_repository_url" {
  value = aws_ecr_repository.lambda["log-enricher"].repository_url
}

output "dashboard_generator_repository_url" {
  value = aws_ecr_repository.lambda["dashboard-generator"].repository_url
}
