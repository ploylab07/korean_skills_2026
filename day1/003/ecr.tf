resource "aws_ecr_repository" "book" {
  name                 = "wsc2026-book-ecr"
  image_tag_mutability = "MUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "v1*"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

# Push :v1.0.0 via CodeBuild (mark.sh 3-1 expects this tag after apply)
module "book_image" {
  source = "../../build/modules/ecr-codebuild"

  name_prefix         = "wsc2026-book"
  region              = var.region
  account_id          = local.account_id
  ecr_repository_name = aws_ecr_repository.book.name
  ecr_repository_url  = aws_ecr_repository.book.repository_url
  ecr_kms_key_arn     = aws_kms_key.ecr.arn
  context_dir         = path.module
  dockerfile          = "Dockerfile"
  image_tags          = ["v1.0.0"]
  excludes = [
    ".terraform",
    ".terraform/**",
    "*.tf",
    "*.tfvars",
    "*.md",
    "*.sh",
    "scripts",
    "scripts/**",
    "mark.sh",
    ".git",
    ".git/**",
    "terraform.tfstate*",
    "k8s",
    "k8s/**",
    "lambda",
    "lambda/**",
    "클라우드컴퓨팅_1과제.pdf",
    "클라우드컴퓨팅_1과제 채점.pdf",
  ]

  depends_on = [aws_ecr_repository.book]
}

resource "null_resource" "book_image" {
  triggers = {
    build = module.book_image.build_complete
    tag   = "v1.0.0"
  }

  depends_on = [module.book_image]
}
