resource "aws_ecr_repository" "about" {
  name                 = "wsi-about"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "wsi-about"
  }
}

resource "aws_ecr_repository" "projects" {
  name                 = "wsi-projects"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "wsi-projects"
  }
}

resource "null_resource" "docker_build_push" {
  count = var.build_and_push_images ? 1 : 0

  triggers = {
    about_dockerfile = filemd5("${path.module}/apps/about/Dockerfile")
    about_app        = filemd5("${path.module}/apps/about/app.py")
    projects_docker  = filemd5("${path.module}/apps/projects/Dockerfile")
    projects_app     = filemd5("${path.module}/apps/projects/app.py")
    about_repo       = aws_ecr_repository.about.name
    projects_repo    = aws_ecr_repository.projects.name
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/build-and-push.sh"
    working_dir = path.module
    environment = {
      AWS_REGION        = var.aws_region
      ABOUT_REPO_URL    = aws_ecr_repository.about.repository_url
      PROJECTS_REPO_URL = aws_ecr_repository.projects.repository_url
    }
  }

  depends_on = [
    aws_ecr_repository.about,
    aws_ecr_repository.projects,
  ]
}
