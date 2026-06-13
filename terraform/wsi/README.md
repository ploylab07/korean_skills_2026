# 2023 지방기능경기대회 — Web Service Provisioning (Terraform)

2023년 클라우드컴퓨팅 **제1과제(Web Service Provisioning)** 요구사항을 Terraform으로 구현한 코드입니다.

## 빠른 시작

```bash
cd terraform/wsi

# 1) 변수 파일 준비
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 에서 key_name 수정

# 2) 초기화 & 배포
terraform init
terraform plan
terraform apply

# 3) Docker 이미지 ECR 푸시 (Bastion 또는 로컬)
export AWS_REGION=ap-northeast-2
export ABOUT_REPO_URL=$(terraform output -raw ecr_about_repository_url)
export PROJECTS_REPO_URL=$(terraform output -raw ecr_projects_repository_url)
./scripts/build-and-push.sh

# 4) ECS 서비스 재배포 (이미지 반영)
aws ecs update-service --cluster wsi-ecs --service wsi-about-svc --force-new-deployment --region ap-northeast-2
aws ecs update-service --cluster wsi-ecs --service wsi-projects-svc --force-new-deployment --region ap-northeast-2

# 5) 접속 확인
terraform output cloudfront_url_about
terraform output cloudfront_url_projects
```

## 상세 가이드

초보자용 전체 설명서: [docs/TERRAFORM_GUIDE.md](../../docs/TERRAFORM_GUIDE.md)

## 파일 구조

| 파일 | 역할 |
|---|---|
| `vpc.tf` | VPC, Subnet, IGW, NAT, Route Table |
| `bastion.tf` | Bastion EC2 + Elastic IP |
| `iam.tf` | Bastion PowerUser, ECS Task Role |
| `security_groups.tf` | Bastion/ALB/ECS Security Group |
| `ecr.tf` | ECR 리포지토리 |
| `ecs.tf` | ECS Cluster, Task Definition, Service |
| `alb.tf` | ALB, Target Group, Path 라우팅 |
| `cloudfront.tf` | CloudFront (HTTPS, 캐시 정책) |
| `apps/` | Flask 웹 애플리케이션 소스 |
| `scripts/build-and-push.sh` | Docker 빌드 & ECR 푸시 |

## 요구사항 대응 요약

| 과제 항목 | 구현 |
|---|---|
| VPC 10.0.0.0/16 | `vpc.tf` |
| Public/Private Subnet 2AZ | `vpc.tf` |
| Bastion + 고정 Public IP | `bastion.tf` + EIP |
| Bastion PowerUserAccess | `iam.tf` |
| ECR wsi-about / wsi-projects | `ecr.tf` |
| ECS Fargate (Private Subnet) | `ecs.tf` |
| ALB path 라우팅 | `alb.tf` |
| CloudFront HTTPS + 캐시 | `cloudfront.tf` |
| ALB는 CloudFront만 허용 | CloudFront managed prefix list SG |

## 삭제

```bash
terraform destroy
```

> NAT Gateway, EIP, ALB 등은 시간당 과금됩니다. 연습 후 반드시 `destroy` 하세요.
