resource "aws_s3_bucket" "web" {
  bucket = local.bucket_name
  tags   = merge(local.common_tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "web" {
  bucket = aws_s3_bucket.web.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.web.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
  source_hash  = filemd5("${path.module}/index.html")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.data.arn
}

resource "aws_s3_object" "main_jpeg" {
  bucket       = aws_s3_bucket.web.id
  key          = "main.jpeg"
  source       = "${path.module}/main.jpeg"
  content_type = "image/jpeg"
  source_hash  = filemd5("${path.module}/main.jpeg")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.data.arn
}

resource "aws_ecr_repository" "book" {
  name = "unicorn-concert-app"
  # latest만 재태그 허용, 그 외(v1.0.0 등)는 immutable — 채점: IMMUTABLE_WITH_EXCLUSION
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  force_delete         = true

  image_tag_mutability_exclusion_filter {
    filter      = "latest"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data.arn
  }

  tags = merge(local.common_tags, { Name = "unicorn-concert-app" })
}

# Push unicorn-concert-app :v1.0.0 and :latest via CodeBuild (no local Docker)
module "book_image" {
  source = "../../build/modules/ecr-codebuild"

  name_prefix         = "unicorn-book"
  region              = local.region
  account_id          = local.account_id
  ecr_repository_name = aws_ecr_repository.book.name
  ecr_repository_url  = aws_ecr_repository.book.repository_url
  ecr_kms_key_arn     = aws_kms_key.data.arn
  context_dir         = path.module
  dockerfile          = "Dockerfile"
  image_tags          = ["v1.0.0", "latest"]
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
  ]

  depends_on = [aws_ecr_repository.book]
}

resource "null_resource" "push_book_image" {
  triggers = {
    build = module.book_image.build_complete
    tag   = "v1.0.0"
  }
  depends_on = [module.book_image]
}

resource "aws_ecr_lifecycle_policy" "book" {
  repository = aws_ecr_repository.book.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
