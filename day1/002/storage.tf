resource "aws_ecr_repository" "book" {
  name                 = "wskorea26-book-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

# Push book image as :stable via CodeBuild (no local Docker Desktop)
module "book_image" {
  source = "../../build/modules/ecr-codebuild"

  name_prefix          = "wskorea26-book"
  region               = var.region
  account_id           = local.account_id
  ecr_repository_name  = aws_ecr_repository.book.name
  ecr_repository_url   = aws_ecr_repository.book.repository_url
  ecr_kms_key_arn      = aws_kms_key.ecr.arn
  context_dir          = path.module
  dockerfile           = "Dockerfile"
  image_tags           = ["stable"]
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
    "main.jpeg",
    "index.html",
    "error.html",
    "web",
    "web/**",
  ]

  depends_on = [aws_ecr_repository.book]
}

# Alias for existing depends_on references (k8s.tf)
resource "null_resource" "book_image" {
  triggers = {
    build = module.book_image.build_complete
    tag   = "stable" # ECR :stable
  }
  depends_on = [module.book_image]
}

resource "aws_dynamodb_table" "data" {
  name                        = "wskorea26-data-table"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "client_id"
  deletion_protection_enabled = true

  attribute {
    name = "client_id"
    type = "S"
  }

  attribute {
    name = "concert_name"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "concert_name-created_at-index"
    hash_key        = "concert_name"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  tags = { Name = "wskorea26-data-table" }
}
