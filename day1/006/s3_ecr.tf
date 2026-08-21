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
      kms_master_key_id = aws_kms_key.s3.arn
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
  kms_key_id             = aws_kms_key.s3.arn
}

resource "aws_s3_object" "main_jpeg" {
  bucket       = aws_s3_bucket.web.id
  key          = "main.jpeg"
  source       = "${path.module}/main.jpeg"
  content_type = "image/jpeg"
  source_hash  = filemd5("${path.module}/main.jpeg")

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.s3.arn
}

resource "aws_ecr_repository" "book" {
  name                 = "book"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { Name = "book" })
}

resource "aws_ecr_repository" "hostname_bootstrap" {
  name                 = "hostname-bootstrap"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, { Name = "hostname-bootstrap" })
}

# Push hostname-bootstrap BEFORE node groups (Bottlerocket essential bootstrap).
# Windows contest PCs have no Docker Desktop — CodeBuild builds/pushes.
module "hostname_bootstrap_image" {
  source = "../../build/modules/ecr-codebuild"

  name_prefix         = "gj2026-hostname-bootstrap"
  region              = local.region
  account_id          = local.account_id
  ecr_repository_name = aws_ecr_repository.hostname_bootstrap.name
  ecr_repository_url  = aws_ecr_repository.hostname_bootstrap.repository_url
  context_dir         = "${path.module}/bootstrap"
  dockerfile          = "Dockerfile"
  image_tags          = ["latest"]
  # Default module excludes *.sh — we need set-hostname.sh in the image context.
  excludes = [
    ".terraform",
    ".terraform/**",
    "*.tf",
    "*.tfvars",
    "*.md",
    ".git",
    ".git/**",
    "terraform.tfstate*",
    ".build",
    ".build/**",
  ]

  depends_on = [aws_ecr_repository.hostname_bootstrap]
}

# Book image for Windows apply (no local Docker). Nodes do not need this to join,
# but post-deploy / workloads do — build during apply so start.cmd is enough.
module "book_image" {
  source = "../../build/modules/ecr-codebuild"

  name_prefix         = "gj2026-book"
  region              = local.region
  account_id          = local.account_id
  ecr_repository_name = aws_ecr_repository.book.name
  ecr_repository_url  = aws_ecr_repository.book.repository_url
  context_dir         = path.module
  dockerfile          = "Dockerfile"
  image_tags          = ["latest"]
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
    "run-mark.sh",
    "post-deploy.sh",
    "deploy-k8s.sh",
    "build-push-image.sh",
    "fix-node-names.sh",
    "bootstrap",
    "bootstrap/**",
    "k8s",
    "k8s/**",
    "build",
    "build/**",
    ".git",
    ".git/**",
    "terraform.tfstate*",
    "*.pdf",
    "main.jpeg",
    "index.html",
  ]

  depends_on = [aws_ecr_repository.book]
}
