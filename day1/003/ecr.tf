resource "aws_ecr_repository" "book" {
  name                 = "wsc2026-book-ecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.keys["wsc2026-ecr-kms"].arn
  }

  tags = merge(local.common_tags, { Name = "wsc2026-book-ecr" })
}

resource "null_resource" "ecr_settings" {
  triggers = {
    repo = aws_ecr_repository.book.name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      source "${path.module}/../../build/load-env.sh"
      load_repo_env "${path.module}/../../build"
      aws ecr put-image-tag-mutability \
        --repository-name wsc2026-book-ecr \
        --image-tag-mutability MUTABLE_WITH_EXCLUSION \
        --image-tag-mutability-exclusion-filters '[{"filter":"v1*","filterType":"WILDCARD"}]'
    EOT
  }

  depends_on = [aws_ecr_repository.book]
}

resource "null_resource" "ecr_push" {
  triggers = {
    image_hash = filemd5("${path.module}/book-linux-amd64_v1.0.1")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      source "${path.module}/../../build/load-env.sh"
      load_repo_env "${path.module}/../../build"
      ACCOUNT_ID=${local.account_id}
      REGION=${var.region}
      aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
      cd "${path.module}"
      docker build -t wsc2026-book-ecr:v1.0.0 -f Dockerfile .
      docker tag wsc2026-book-ecr:v1.0.0 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/wsc2026-book-ecr:v1.0.0
      docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/wsc2026-book-ecr:v1.0.0
    EOT
  }

  depends_on = [null_resource.ecr_settings]
}
