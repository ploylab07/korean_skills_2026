output "codebuild_project_name" {
  value = aws_codebuild_project.image.name
}

output "source_bucket" {
  value = aws_s3_bucket.source.bucket
}

output "image_tags" {
  value = var.image_tags
}

output "build_complete" {
  description = "Depend on this to wait until the image is in ECR"
  value       = null_resource.run_build.id
}
