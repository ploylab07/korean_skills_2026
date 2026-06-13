variable "aws_region" {
  description = "AWS 리전 (과제 요구: ap-northeast-2)"
  type        = string
  default     = "ap-northeast-2"
}

variable "key_name" {
  description = "Bastion SSH 접속용 EC2 Key Pair 이름 (AWS 콘솔에서 미리 생성)"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "Bastion SSH 허용 CIDR"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ecs_desired_count" {
  description = "각 ECS 서비스의 desired task 수 (가용영역 분산)"
  type        = number
  default     = 2
}

variable "build_and_push_images" {
  description = "true이면 terraform apply 시 Docker 이미지를 빌드하여 ECR에 푸시"
  type        = bool
  default     = false
}
