# Terraform 설명서 — 2023 Web Service Provisioning

> **대상**: Terraform과 AWS를 처음 접하는 분  
> **과제**: 2023 지방기능경기대회 클라우드컴퓨팅 제1과제 (Web Service Provisioning)  
> **코드 위치**: `terraform/wsi/`

---

## 목차

1. [Terraform이란?](#1-terraform이란)
2. [이 과제에서 만드는 아키텍처](#2-이-과제에서-만드는-아키텍처)
3. [사전 준비](#3-사전-준비)
4. [프로젝트 파일 구조 이해하기](#4-프로젝트-파일-구조-이해하기)
5. [Terraform 핵심 개념](#5-terraform-핵심-개념)
6. [배포 단계별 가이드](#6-배포-단계별-가이드)
7. [과제 요구사항 ↔ 코드 매핑](#7-과제-요구사항--코드-매핑)
8. [동작 확인 방법](#8-동작-확인-방법)
9. [자주 하는 실수 & 트러블슈팅](#9-자주-하는-실수--트러블슈팅)
10. [비용 절약 & 리소스 삭제](#10-비용-절약--리소스-삭제)

---

## 1. Terraform이란?

**Terraform**은 클라우드 인프라를 **코드(Infrastructure as Code, IaC)** 로 관리하는 도구입니다.

콘솔에서 클릭으로 VPC, EC2, ECS를 만드는 대신, `.tf` 파일에 원하는 상태를 적어 두고 Terraform이 AWS에 반영합니다.

| 콘솔 방식 | Terraform 방식 |
|---|---|
| 수동 클릭, 스크린샷으로 기록 | 코드로 재현 가능 |
| 실수 시 추적 어려움 | Git으로 변경 이력 관리 |
| 동일 환경 재구축이 번거로움 | `terraform apply` 한 번으로 재구축 |

### Terraform의 4단계 워크플로

```bash
terraform init      # 플러그인(AWS provider) 다운로드
terraform plan      # 무엇이 생성/변경/삭제될지 미리보기
terraform apply     # 실제 AWS에 반영
terraform destroy   # 만든 리소스 전부 삭제
```

**비유**: `plan`은 설계도 확인, `apply`는 실제 공사, `destroy`는 철거입니다.

---

## 2. 이 과제에서 만드는 아키텍처

```
[사용자 브라우저]
       │ HTTPS
       ▼
[CloudFront]  ── /about 캐시 O, /projects 캐시 X
       │ HTTP (CloudFront IP만 허용)
       ▼
[ALB wsi-alb]  ── /about → about TG, /projects → projects TG
       │
       ├──────────────────────┐
       ▼                      ▼
[ECS Fargate]            [ECS Fargate]
 wsi-about-svc            wsi-projects-svc
 (Private Subnet A/B)     (Private Subnet A/B)
       │                      │
       └──── ECR 이미지 ──────┘

[Bastion EC2] ── Public Subnet A, Elastic IP 고정
       │
       └── SSH 접속 후 awscli 사용 (PowerUser 권한)
```

### 네트워크 구성

| 리소스 | CIDR / 이름 | 역할 |
|---|---|---|
| VPC | 10.0.0.0/16 (`wsi-vpc`) | 전체 네트워크 |
| Public A | 10.0.1.0/24 (`wsi-public-a`) | Bastion, ALB, NAT |
| Public B | 10.0.2.0/24 (`wsi-public-b`) | ALB (다중 AZ) |
| Private A | 10.0.3.0/24 (`wsi-private-a`) | ECS Task |
| Private B | 10.0.4.0/24 (`wsi-private-b`) | ECS Task |

- **Internet Gateway**: Public Subnet → 인터넷
- **NAT Gateway**: Private Subnet → 아웃바운드 인터넷 (ECR 이미지 pull 등)

---

## 3. 사전 준비

### 3-1. 필요한 도구

| 도구 | 용도 | 설치 확인 |
|---|---|---|
| Terraform | 인프라 코드 실행 | `terraform version` |
| AWS CLI | AWS API 호출 | `aws --version` |
| Docker | 이미지 빌드 & ECR 푸시 | `docker --version` |
| Git | 코드 관리 | `git --version` |

#### Terraform 설치 (Linux 예시)

```bash
# HashiCorp 공식 릴리스에서 다운로드하거나 패키지 매니저 사용
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

### 3-2. AWS 자격 증명 설정

경기 계정 또는 개인 계정의 Access Key를 설정합니다.

```bash
aws configure
# AWS Access Key ID: (입력)
# AWS Secret Access Key: (입력)
# Default region name: ap-northeast-2
# Default output format: json
```

확인:

```bash
aws sts get-caller-identity
```

### 3-3. EC2 Key Pair 생성

Bastion SSH 접속에 필요합니다. **서울 리전(ap-northeast-2)** 에서 생성하세요.

```bash
aws ec2 create-key-pair \
  --key-name wsi-key \
  --query 'KeyMaterial' \
  --output text \
  --region ap-northeast-2 > ~/.ssh/wsi-key.pem

chmod 400 ~/.ssh/wsi-key.pem
```

### 3-4. IAM 권한

Terraform 실행 계정에는 최소한 아래 서비스 생성 권한이 필요합니다.

- VPC, EC2, ECS, ECR, ELB, CloudFront, IAM (역할/인스턴스 프로파일)

경기장에서는 보통 **AdministratorAccess** 또는 이에 준하는 권한이 부여됩니다.

---

## 4. 프로젝트 파일 구조 이해하기

```
terraform/wsi/
├── versions.tf          # Terraform & Provider 버전, AWS provider 설정
├── variables.tf         # 입력 변수 (key_name, region 등)
├── locals.tf            # 내부 상수 (CIDR, AZ 매핑)
├── vpc.tf               # VPC, Subnet, IGW, NAT, Route Table
├── security_groups.tf   # 보안 그룹
├── iam.tf               # IAM Role (Bastion, ECS)
├── bastion.tf           # Bastion EC2 + Elastic IP
├── ecr.tf               # ECR 리포지토리
├── ecs.tf               # ECS Cluster, Task, Service
├── alb.tf               # Application Load Balancer
├── cloudfront.tf        # CloudFront Distribution
├── outputs.tf           # apply 후 출력값 (URL, IP 등)
├── terraform.tfvars.example  # 변수 예시 (복사해서 사용)
├── apps/
│   ├── about/           # About Flask 앱 + Dockerfile
│   └── projects/        # Projects Flask 앱 + Dockerfile
└── scripts/
    └── build-and-push.sh  # Docker 빌드 & ECR 푸시 스크립트
```

### 파일을 나눈 이유

하나의 거대한 `main.tf`에 전부 넣어도 동작은 합니다. 하지만 역할별로 나누면:

- 과제 항목별로 코드를 찾기 쉽고
- 수정 시 영향 범위가 명확하며
- 팀 작업·채점 대비에 유리합니다.

---

## 5. Terraform 핵심 개념

### 5-1. Provider

**Provider**는 Terraform이 어떤 클라우드와 통신할지 정의합니다.

```hcl
provider "aws" {
  region = "ap-northeast-2"
}
```

### 5-2. Resource

**Resource**는 실제로 만들 AWS 객체입니다.

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "wsi-vpc"
  }
}
```

- `aws_vpc` : 리소스 타입
- `"main"` : Terraform 내부 이름 (다른 파일에서 참조할 때 사용)
- `tags.Name` : AWS 콘솔에 보이는 이름 (채점 시 중요!)

### 5-3. Variable & Output

**Variable** — 외부에서 값을 받습니다.

```hcl
variable "key_name" {
  description = "EC2 Key Pair 이름"
  type        = string
}
```

`terraform.tfvars` 파일에 실제 값을 넣습니다.

**Output** — apply 후 필요한 정보를 출력합니다.

```hcl
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.main.domain_name
}
```

### 5-4. Data Source

이미 존재하는 AWS 데이터를 **조회만** 합니다 (생성하지 않음).

```hcl
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  # ...
}
```

### 5-5. State (상태 파일)

Terraform은 `terraform.tfstate`에 **현재 AWS에 무엇이 있는지** 기록합니다.

- 이 파일이 없으면 Terraform은 자신이 만든 리소스를 추적할 수 없습니다.
- **절대 Git에 올리지 마세요** (민감 정보 포함 가능). `.gitignore`에 이미 등록되어 있습니다.

### 5-6. Plan vs Apply

| 명령 | 설명 |
|---|---|
| `terraform plan` | 변경 사항 **미리보기** (실제 변경 없음) |
| `terraform apply` | plan 내용을 **실제 반영** |
| `terraform destroy` | 이 코드로 만든 리소스 **삭제** |

`plan` 결과에서 `+ create`, `~ update`, `- destroy` 기호를 확인하세요.

---

## 6. 배포 단계별 가이드

### Step 0 — 프로젝트 폴더로 이동

```bash
cd ~/projects/korean_skills_2026/terraform/wsi
```

### Step 1 — 변수 파일 작성

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` 를 열어 Key Pair 이름을 수정합니다.

```hcl
key_name = "wsi-key"   # 본인이 만든 Key Pair 이름
```

### Step 2 — terraform init

```bash
terraform init
```

**하는 일**: AWS Provider 플러그인 다운로드, `.terraform/` 폴더 생성

처음 한 번만 실행하면 됩니다. provider 버전이 바뀌면 다시 실행합니다.

### Step 3 — terraform plan

```bash
terraform plan
```

**하는 일**: 앞으로 생성될 리소스 목록 확인

에러가 없고 `Plan: XX to add, 0 to change, 0 to destroy` 형태면 정상입니다.

### Step 4 — terraform apply

```bash
terraform apply
```

`yes` 입력 후 10~20분 정도 소요될 수 있습니다. (NAT Gateway, CloudFront 등)

완료 후 출력 예시:

```
bastion_public_ip      = "1.2.3.4"
cloudfront_url_about   = "https://d1234abcd.cloudfront.net/about"
cloudfront_url_projects = "https://d1234abcd.cloudfront.net/projects"
```

### Step 5 — Docker 이미지 빌드 & ECR 푸시

ECS는 ECR에 이미지가 있어야 Task가 기동됩니다. **apply 직후에는 이미지가 없을 수 있으므로** 이 단계가 필수입니다.

#### 방법 A: 로컬 PC에서 (Docker 설치된 경우)

```bash
export AWS_REGION=ap-northeast-2
export ABOUT_REPO_URL=$(terraform output -raw ecr_about_repository_url)
export PROJECTS_REPO_URL=$(terraform output -raw ecr_projects_repository_url)

./scripts/build-and-push.sh
```

#### 방법 B: Bastion EC2에서

```bash
# 로컬에서 Bastion 접속
ssh -i ~/.ssh/wsi-key.pem ec2-user@$(terraform output -raw bastion_public_ip)

# Bastion에서 (Docker 설치 필요 시)
sudo amazon-linux-extras install docker -y
sudo systemctl start docker
sudo usermod -aG docker ec2-user
# 재접속 후

git clone <본인-저장소-URL>
cd korean_skills_2026/terraform/wsi

export AWS_REGION=ap-northeast-2
export ABOUT_REPO_URL=<ECR about URL>
export PROJECTS_REPO_URL=<ECR projects URL>
./scripts/build-and-push.sh
```

> Bastion에는 PowerUserAccess가 붙어 있어 **어떤 Linux 사용자로 awscli를 실행해도** ECR push가 가능합니다.

### Step 6 — ECS 서비스 재배포

이미지 푸시 후 ECS가 새 이미지를 받도록 합니다.

```bash
aws ecs update-service --cluster wsi-ecs --service wsi-about-svc --force-new-deployment --region ap-northeast-2
aws ecs update-service --cluster wsi-ecs --service wsi-projects-svc --force-new-deployment --region ap-northeast-2
```

Target Group이 **healthy** 될 때까지 2~5분 기다립니다.

### Step 7 — (선택) 이미지 자동 푸시

로컬에 Docker가 있고 apply와 동시에 푸시하려면:

```hcl
# terraform.tfvars
build_and_push_images = true
```

이 경우 `ecr.tf`의 `null_resource`가 apply 중 이미지를 빌드합니다.

---

## 7. 과제 요구사항 ↔ 코드 매핑

### Cloud Networking (`vpc.tf`)

| 요구사항 | 코드 |
|---|---|
| VPC 10.0.0.0/16, Name=wsi-vpc | `aws_vpc.main` |
| wsi-public-a/b | `aws_subnet.public` |
| wsi-private-a/b | `aws_subnet.private` |
| wsi-public-rtb | `aws_route_table.public` |
| wsi-private-rtb-a/b | `aws_route_table.private_a/b` |
| Internet Gateway | `aws_internet_gateway.main` |
| NAT Gateway | `aws_nat_gateway.main` |

### Bastion (`bastion.tf`, `iam.tf`)

| 요구사항 | 코드 |
|---|---|
| t3.small, Amazon Linux 2 | `aws_instance.bastion` |
| wsi-public-a 서브넷 | `subnet_id = aws_subnet.public["a"].id` |
| stop/start 후 IP 유지 | `aws_eip` + `aws_eip_association` |
| PowerUserAccess | `aws_iam_role_policy_attachment.bastion_power_user` |
| awscli, curl 설치 | `user_data` 스크립트 |
| Name=wsi-bastion | `tags.Name` |
| outbound 전체 허용 | `aws_security_group.bastion` egress |

### ECR (`ecr.tf`)

| 요구사항 | 코드 |
|---|---|
| wsi-about, wsi-projects | `aws_ecr_repository.about/projects` |
| scan_on_push | `image_scanning_configuration` |
| latest 태그 | `build-and-push.sh` |

> **취약점 스캔**: `python:3.8-slim-bookworm` + 최소 패키지로 Low 이상 취약점을 피합니다. 푸시 후 ECR 콘솔에서 스캔 결과를 확인하세요.

### ECS (`ecs.tf`)

| 요구사항 | 코드 |
|---|---|
| Cluster wsi-ecs | `aws_ecs_cluster.main` |
| Fargate, Private Subnet | `launch_type = "FARGATE"`, private subnets |
| about-task-def / projects-task-def | `aws_ecs_task_definition` |
| wsi-about-svc / wsi-projects-svc | `aws_ecs_service` |
| 포트 5000 | `portMappings` |
| ALB 트래픽만 허용 | ECS SG ingress from ALB SG only |
| 다중 AZ | `desired_count = 2`, subnet A+B |

> 과제 문서에 "EC2에서 실행"과 "Fargate"가 함께 적혀 있습니다. **후자(Fargate)** 가 서비스 실행 방식의 최종 요구사항으로 해석하여 Fargate로 구현했습니다.

### ALB (`alb.tf`)

| 요구사항 | 코드 |
|---|---|
| wsi-alb | `aws_lb.main` |
| /about → wsi-about-tg | `aws_lb_listener_rule.about` |
| /projects → wsi-projects-tg | `aws_lb_listener_rule.projects` |
| CloudFront만 허용 | ALB SG + CloudFront managed prefix list |

### CloudFront (`cloudfront.tf`)

| 요구사항 | 코드 |
|---|---|
| HTTPS 접근 | `viewer_protocol_policy = "redirect-to-https"` |
| Origin = ALB | `origin.domain_name = aws_lb.main.dns_name` |
| 전 세계 Edge | `price_class = "PriceClass_All"` |
| IPv6 비활성화 | `is_ipv6_enabled = false` |
| /about 캐시 | `ordered_cache_behavior` (TTL > 0) |
| /projects 비캐시 | `ordered_cache_behavior` (TTL = 0) |

---

## 8. 동작 확인 방법

### 8-1. CloudFront URL 접속

```bash
curl -s "$(terraform output -raw cloudfront_url_about)"
# 기대 출력: The about page

curl -s "$(terraform output -raw cloudfront_url_projects)"
# 기대 출력: The projects page
```

브라우저에서도 HTTPS로 접속해 보세요.

### 8-2. ECS Task 상태

```bash
aws ecs describe-services \
  --cluster wsi-ecs \
  --services wsi-about-svc wsi-projects-svc \
  --region ap-northeast-2 \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount}'
```

`running == desired` 이어야 합니다.

### 8-3. Target Group Health

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names wsi-about-tg --query 'TargetGroups[0].TargetGroupArn' --output text --region ap-northeast-2) \
  --region ap-northeast-2
```

`State`가 `healthy` 여야 합니다.

### 8-4. Bastion EIP 확인

```bash
# 인스턴스 stop/start 후에도 동일 IP인지 확인
aws ec2 describe-addresses --filters "Name=tag:Name,Values=wsi-bastion-eip" --region ap-northeast-2
```

### 8-5. ECR 이미지 스캔

```bash
aws ecr describe-image-scan-findings \
  --repository-name wsi-about \
  --image-id imageTag=latest \
  --region ap-northeast-2
```

---

## 9. 자주 하는 실수 & 트러블슈팅

### ECS Task가 `CannotPullContainerError`

**원인**: ECR에 `latest` 이미지가 없음  
**해결**: `./scripts/build-and-push.sh` 실행 후 `force-new-deployment`

### Target Group `unhealthy`

**원인**: 앱이 5000 포트에서 응답하지 않거나 health check path 불일치  
**해결**:

- Flask 앱에 `/about`, `/projects` 라우트가 있는지 확인
- Security Group이 ALB → ECS 5000 허용하는지 확인

### CloudFront 502/504

**원인**: ALB Target이 unhealthy 이거나 CloudFront → ALB SG 차단  
**해결**: Target health 확인, ALB SG에 CloudFront prefix list 적용 확인

### `terraform apply` IAM 오류

**원인**: 실행 계정 권한 부족  
**해결**: IAM 정책 확인. `iam:CreateRole`, `iam:PassRole` 필요

### Key Pair 오류

```
Error: InvalidKeyPair.NotFound
```

**해결**: `ap-northeast-2` 리전에 Key Pair가 있는지, `terraform.tfvars`의 `key_name`이 정확한지 확인

### NAT Gateway 비용

NAT Gateway는 **시간당 과금**됩니다. 연습이 끝나면 반드시 `terraform destroy` 하세요.

### Terraform state 충돌

여러 사람이 같은 state로 동시 apply하면 안 됩니다. 개인 연습 시 로컬 state로 충분합니다.

---

## 10. 비용 절약 & 리소스 삭제

### 비용이 큰 리소스

| 리소스 | 참고 |
|---|---|
| NAT Gateway | 시간당 + 데이터 전송 비용 |
| ALB | 시간당 LCU 비용 |
| CloudFront | 트래픽 기반 (적은 테스트는 저렴) |
| Fargate Task | vCPU/메모리 시간당 |
| EIP | 인스턴스에 연결되어 있으면 무료 |

### 전체 삭제

```bash
cd terraform/wsi
terraform destroy
```

`yes` 입력 후 모든 리소스가 제거됩니다.

### 경기장 유의사항

1. **Bastion EC2를 terminate 하지 마세요** — 채점에 사용됩니다.
2. **모든 리소스는 ap-northeast-2** 에 있어야 합니다.
3. **비용 한도**를 넘기면 계정이 정지될 수 있습니다.
4. Security Group **80/443 outbound any open** 은 과제에서 허용됩니다.

---

## 부록: Terraform 명령어 치트시트

| 명령어 | 설명 |
|---|---|
| `terraform fmt` | 코드 포맷 자동 정리 |
| `terraform validate` | 문법 검증 |
| `terraform plan -out=plan.out` | plan 결과를 파일로 저장 |
| `terraform apply plan.out` | 저장된 plan 적용 |
| `terraform state list` | 관리 중인 리소스 목록 |
| `terraform show` | state 상세 보기 |
| `terraform output` | output 값 출력 |
| `terraform import` | 기존 AWS 리소스를 state에 가져오기 (고급) |

---

## 부록: 코드 수정 시 팁

1. **이름(Name 태그)은 과제 그대로** — 채점 스크립트가 이름으로 찾습니다.
2. **한 파일만 수정했어도** `terraform plan`으로 영향 범위를 확인하세요.
3. **모르면 콘솔에서 만든 리소스 이름**과 `.tf`의 `tags.Name`을 대조하세요.
4. **Flask 배포 파일은 과제에서 수정 금지** — 제공된 파일 그대로 Docker 이미지에 넣으세요.

---

## 다음 학습 순서 (추천)

1. `vpc.tf`만 apply 해 보기 (VPC 모듈 이해)
2. Bastion 추가 후 SSH 접속
3. ECR + ECS + ALB 순서로 확장
4. 마지막에 CloudFront 연결
5. `terraform destroy`로 철거 연습

---

**문의/개선**: 이 설명서는 `terraform/wsi` 코드와 함께 업데이트하세요.  
화이팅!
