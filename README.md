# Korean Skills 2026

클라우드 컴퓨팅 경기대회 문제를 풀기 위한 **Terraform IaC(인프라 자동화)** 학습 저장소입니다.

이 README만 따라 하면, **Terraform을 PC에 따로 설치하지 않고** clone → AWS 배포 → 삭제까지 처음부터 끝까지 해볼 수 있습니다.

**Windows 대회/배포만 빠르게:** [docs/WINDOWS_DEPLOY.md](docs/WINDOWS_DEPLOY.md) — `.\start.cmd` 설정·과제 목록·Apply/Destroy 절차

---

## 목차

1. [이 저장소는 무엇인가요?](#1-이-저장소는-무엇인가요)
2. [폴더 구조](#2-폴더-구조)
3. [사전 준비](#3-사전-준비)
4. [빠른 시작 — 5분 요약](#4-빠른-시작--5분-요약)
5. [처음부터 끝까지 따라하기 (연습 배포)](#5-처음부터-끝까지-따라하기-연습-배포)
6. [Terraform 명령어 정리](#6-terraform-명령어-정리)
7. [AWS 키 설정 / 변경](#7-aws-키-설정--변경)
8. [Git 브랜치 전략](#8-git-브랜치-전략)
9. [경기 과제 작업 흐름](#9-경기-과제-작업-흐름)
10. [Cursor AI로 작업하기](#10-cursor-ai로-작업하기)
11. [자주 발생하는 문제](#11-자주-발생하는-문제)
12. [참고 문서](#12-참고-문서)

---

## 1. 이 저장소는 무엇인가요?

| 항목 | 설명 |
|------|------|
| 목적 | 클라우드 컴퓨팅 문제의 AWS 인프라를 Terraform 코드로 구현 |
| 특징 | `git clone`만 하면 Terraform 실행 환경이 준비됨 (별도 설치 불필요) |
| 작업 단위 | `day1/`, `day2/`, `day3/` 등 날짜·과제별 폴더 |
| 목표 | 문제 명세와 **채점 기준 만점** 충족 |

### Terraform이란?

AWS 콘솔에서 클릭으로 VPC·EC2를 만드는 대신, **코드(.tf 파일)** 로 인프라를 정의하고 한 번에 배포하는 도구입니다.

| 명령 | 의미 | 비유 |
|------|------|------|
| `init` | 플러그인 다운로드 | 도구 준비 |
| `plan` | 변경 계획 미리보기 | 설계도 확인 |
| `apply` | AWS에 실제 반영 | 공사 |
| `destroy` | 만든 리소스 전부 삭제 | 철거 |

---

## 2. 폴더 구조

```
korean_skills_2026/
├── README.md              ← 지금 보고 있는 가이드 (전체 흐름)
├── terraform.cmd          ← Windows용 Terraform 실행
├── terraform              ← Mac/Linux/Git Bash용 Terraform 실행
├── setup-aws.cmd          ← Windows용 AWS 키 입력
├── setup-aws              ← Mac/Linux용 AWS 키 입력
├── .env.example           ← AWS 키 템플릿
├── day1/                  ← Day 1 과제 Terraform 코드
├── day2/                  ← Day 2 과제
├── day3/                  ← Day 3 과제
├── build/                 ← Terraform 자동 다운로드 도구 (상세: build/README.md)
├── docs/                  ← 과제별 상세 설명서
│   ├── WINDOWS_DEPLOY.md  ← Windows start.cmd 배포 가이드
│   └── TERRAFORM_GUIDE.md
├── start.cmd              ← Windows 원클릭 배포 (과제 선택 → apply)
└── .cursor/rules/         ← Cursor AI 작업 규칙
```

> **중요:** Windows에서는 `terraform`이 아니라 **`terraform.cmd`** 를 사용하세요.  
> Mac/Linux에서는 **`./terraform`** (`./` 필수)를 사용하세요.

---

## 3. 사전 준비

### 필수

| 항목 | Windows | Mac / Linux |
|------|---------|-------------|
| Git | [git-scm.com](https://git-scm.com/) | 보통 기본 설치 또는 `brew install git` |
| 인터넷 | 최초 Terraform 다운로드용 | 동일 |
| AWS 계정 + Access Key | IAM에서 발급 | 동일 |

### 불필요 (이 레포가 대신 해줌)

- ❌ `choco install terraform`
- ❌ `brew install terraform`
- ❌ `apt install terraform`
- ❌ 수동 `export AWS_...` (setup-aws 사용 시)

### AWS Access Key 발급 방법 (처음이라면)

1. [AWS 콘솔](https://console.aws.amazon.com/) 로그인
2. **IAM** → **사용자** → 본인 사용자 선택 (또는 새로 생성)
3. **보안 자격 증명** 탭 → **액세스 키 만들기**
4. `AKIA...` (Access Key ID)와 Secret Access Key를 안전하게 보관

> 경기/연습용 계정이라면 보통 `PowerUserAccess` 또는 문제에서 지정한 권한이 필요합니다.

---

## 4. 빠른 시작 — 5분 요약

### Windows (PowerShell)

```powershell
git clone https://github.com/본인username/korean_skills_2026.git
cd korean_skills_2026
git switch dev

.\terraform.cmd version      # Terraform 자동 다운로드
.\setup-aws.cmd              # AWS 키 입력 → .env 저장

cd day1
..\terraform.cmd init
..\terraform.cmd plan
..\terraform.cmd apply
..\terraform.cmd destroy     # 연습 끝나면 반드시 삭제
```

### Mac / Linux

```bash
git clone https://github.com/본인username/korean_skills_2026.git
cd korean_skills_2026
git switch dev

chmod +x terraform setup-aws   # 최초 1회
./terraform version
./setup-aws

cd day1
../terraform init
../terraform plan
../terraform apply
../terraform destroy
```

---

## 5. 처음부터 끝까지 따라하기 (연습 배포)

아래는 **day1 폴더에 최소 S3 버킷**을 만들어 배포했다가 지우는 연습입니다.  
실제 경기 과제 코드가 없어도 Terraform 흐름을 익힐 수 있습니다.

### Step 0 — 저장소 받기

```bash
# HTTPS 예시 (SSH도 가능)
git clone https://github.com/본인username/korean_skills_2026.git
cd korean_skills_2026
git switch dev
git pull
```

### Step 1 — Terraform 준비 확인

**Windows:**

```powershell
.\terraform.cmd version
```

**Mac / Linux:**

```bash
chmod +x terraform setup-aws
./terraform version
```

`Terraform v1.9.8` 같은 버전이 출력되면 성공입니다.  
첫 실행 시 `build/.bin/`에 바이너리가 자동으로 내려받아집니다.

### Step 2 — AWS 키 입력

**Windows:**

```powershell
.\setup-aws.cmd
```

**Mac / Linux:**

```bash
./setup-aws
```

입력 항목:

```
AWS_ACCESS_KEY_ID:     AKIA...
AWS_SECRET_ACCESS_KEY: (입력 시 화면에 안 보임)
AWS_DEFAULT_REGION:    ap-northeast-2   ← Enter만 눌러도 됨
```

→ 프로젝트 루트 `.env` 파일에 저장됩니다. Git에 올라가지 않습니다.  
이후 `terraform.cmd` / `./terraform` 실행 시 **자동으로 AWS 키가 적용**됩니다.

### Step 3 — 연습용 Terraform 코드 작성

`day1` 폴더에 아래 파일을 만듭니다.

**day1/main.tf**

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "practice" {
  bucket = "ks2026-practice-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "practice"
    Project = "korean-skills-2026"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.practice.bucket
}
```

> 버킷 이름은 전 세계에서 유일해야 해서 계정 ID를 붙였습니다.  
> 이미 같은 이름이 있으면 `ks2026-practice-본인이름-...` 처럼 바꿔 주세요.

### Step 4 — init (초기화)

과제 폴더로 이동한 뒤 `init`을 실행합니다.

**Windows:**

```powershell
cd day1
..\terraform.cmd init
```

**Mac / Linux:**

```bash
cd day1
../terraform init
```

`Terraform has been successfully initialized!` 메시지가 나오면 성공입니다.

### Step 5 — plan (미리보기)

**Windows:** `..\terraform.cmd plan`  
**Mac / Linux:** `../terraform plan`

출력에서 `+ create` 로 S3 버킷이 추가될 예정인지 확인합니다.  
에러 없이 계획이 보이면 다음 단계로 넘어갑니다.

### Step 6 — apply (실제 배포)

**Windows:**

```powershell
..\terraform.cmd apply
```

**Mac / Linux:**

```bash
../terraform apply
```

`Do you want to perform these actions?` 에 **`yes`** 입력.

성공하면 마지막에 `bucket_name = "ks2026-practice-..."` 가 출력됩니다.

**AWS 콘솔에서 확인:**

1. [S3 콘솔](https://s3.console.aws.amazon.com/) 접속
2. 리전이 `ap-northeast-2`(서울)인지 확인
3. 방금 만든 버킷이 보이는지 확인

### Step 7 — output 확인

**Windows:** `..\terraform.cmd output`  
**Mac / Linux:** `../terraform output`

```text
bucket_name = "ks2026-practice-123456789012"
```

### Step 8 — destroy (리소스 삭제) ⚠️ 필수

연습이 끝나면 **반드시 삭제**하세요. 안 지우면 S3 요금이 발생할 수 있습니다.

**Windows:**

```powershell
..\terraform.cmd destroy
```

**Mac / Linux:**

```bash
../terraform destroy
```

`Do you really want to destroy all resources?` 에 **`yes`** 입력.

삭제 후 S3 콘솔에서 버킷이 사라졌는지 확인합니다.

### Step 9 — 정리 (선택)

연습 파일을 Git에 올리지 않으려면 `day1/main.tf`를 삭제하거나, 커밋하지 않으면 됩니다.  
`.terraform/` 폴더와 `terraform.tfstate`는 `.gitignore`에 포함되어 있어 자동으로 제외됩니다.

---

## 6. Terraform 명령어 정리

과제 폴더(`.tf` 파일이 있는 곳)에서 실행합니다.

| 명령 | 설명 | 실제 AWS 변경? |
|------|------|----------------|
| `init` | 플러그인·백엔드 초기화 | ❌ |
| `validate` | 문법 검사 | ❌ |
| `plan` | 변경 계획 미리보기 | ❌ |
| `apply` | 리소스 생성·변경 | ✅ |
| `destroy` | 리소스 전부 삭제 | ✅ |
| `output` | 출력 값 확인 | ❌ |

### Windows / Mac 명령 대응표

| 작업 | Windows (day1 폴더 안) | Mac/Linux (day1 폴더 안) |
|------|------------------------|--------------------------|
| 초기화 | `..\terraform.cmd init` | `../terraform init` |
| 계획 | `..\terraform.cmd plan` | `../terraform plan` |
| 배포 | `..\terraform.cmd apply` | `../terraform apply` |
| 삭제 | `..\terraform.cmd destroy` | `../terraform destroy` |

### 루트에서 특정 폴더 지정하기

폴더 이동 없이 프로젝트 루트에서 실행할 수도 있습니다.

**Windows:**

```powershell
.\terraform.cmd -chdir=day1 plan
.\terraform.cmd -chdir=day1 apply
```

**Mac / Linux:**

```bash
./terraform -chdir=day1 plan
./terraform -chdir=day1 apply
```

### 자동 승인 (주의해서 사용)

확인 프롬프트 없이 실행하려면 `-auto-approve`를 붙입니다.

```powershell
..\terraform.cmd apply -auto-approve
..\terraform.cmd destroy -auto-approve
```

---

## 7. AWS 키 설정 / 변경

### 방법 A — setup-aws (권장)

```powershell
# Windows
.\setup-aws.cmd

# Mac / Linux
./setup-aws
```

### 방법 B — .env.example 복사 후 편집

```bash
cp .env.example .env
# .env 파일을 메모장/에디터로 직접 수정
```

`.env` 내용 예시:

```env
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=ap-northeast-2
```

> `.env`와 `*.tfvars`는 Git에 올라가지 않습니다. 절대 커밋하지 마세요.

---

## 8. Git 브랜치 전략

| 브랜치 | 역할 | 평소 작업 |
|--------|------|-----------|
| `dev` | 개발·작업 중 | ✅ 여기서 작업 |
| `master` | 완성된 안정 버전 | ❌ 직접 push 금지 |

### 평소 작업 흐름

```bash
git switch dev
git pull
# ... Terraform 작업 ...
git add .
git commit -m "feat: day1 S3 연습 완료"
git push origin dev
```

### dev → master 반영 (완성됐을 때만)

```bash
git switch master
git pull
git merge dev
git push origin master
git switch dev
```

### 커밋 메시지 권장 형식

| 접두사 | 의미 | 예시 |
|--------|------|------|
| `feat:` | 새 기능/과제 추가 | `feat: day1 wsi 인프라 구현` |
| `fix:` | 버그 수정 | `fix: security group 규칙 수정` |
| `docs:` | 문서 수정 | `docs: README 업데이트` |

---

## 9. 경기 과제 작업 흐름

실제 경기대회 문제를 풀 때는 아래 순서를 따릅니다.

```
1. 문제 PDF / 명세 확인
2. 채점 기준 항목·배점 확인
3. 문제에서 제공하는 파일·리소스 확인 (AMI, Docker 이미지 등)
4. 작업할 폴더 결정 (day1, day2, terraform/wsi 등)
5. setup-aws 로 AWS 키 설정
6. Terraform 코드 작성 (최소 파일 수로)
7. init → plan → apply
8. 채점 기준 항목 하나씩 대조 검증
9. destroy (연습/테스트 후) 또는 제출
10. dev에 commit & push → 완성 시 master 머지
```

> Cursor AI 사용 시 `.cursor/rules/`에 정의된 규칙에 따라, 작업 전 폴더 확인·채점 기준 만점·AWS 키 질문 등이 자동으로 적용됩니다.

---

## 10. Cursor AI로 작업하기

터미널에서 Cursor Agent를 쓰면 자연어로 Terraform 코드 작성·실행을 도와줍니다.

### 설치 (한 번만)

```bash
curl https://cursor.com/install -fsS | bash
cursor-agent login
```

### 사용 예시

```bash
cd korean_skills_2026
cursor-agent
```

```
> day1 폴더에 문제 명세대로 VPC Terraform 코드 작성해줘
> 채점 기준 확인하고 빠진 항목 있으면 수정해줘
> plan 돌려보고 에러 고쳐줘
```

**좋은 프롬프트:** 어느 폴더에, 무엇을, 어떤 제약으로 — 구체적으로 적기.

---

## 11. 자주 발생하는 문제

### `terraform: command not found` (Windows)

```powershell
# ❌ 시스템 전역 terraform (없을 수 있음)
terraform init

# ✅ 이 레포의 래퍼
.\terraform.cmd init
```

### `terraform: command not found` (Mac/Linux)

```bash
# ❌
terraform init

# ✅
./terraform init
```

### `Error: No valid credential sources found`

AWS 키가 없습니다.

```powershell
.\setup-aws.cmd    # Windows
./setup-aws          # Mac/Linux
```

### `Error: Failed to query available provider packages`

`init`을 먼저 실행하지 않았거나 네트워크 문제입니다.

```bash
../terraform init -upgrade
```

### S3 버킷 이름 Already Exists

버킷 이름은 전 세계 유일해야 합니다. `main.tf`의 `bucket` 값에 본인만의 접미사를 추가하세요.

### apply 후 요금이 걱정될 때

연습이 끝나면 **반드시 destroy** 하세요.

```bash
../terraform destroy
```

### Git push 거부됨

```bash
git pull
git push
```

### Terraform 다운로드 실패

- 인터넷 연결 확인
- `releases.hashicorp.com` 접근 가능 여부 확인
- 바이너리 재다운로드:

```powershell
# Windows
Remove-Item -Recurse -Force build\.bin
.\terraform.cmd version
```

```bash
# Mac/Linux
rm -rf build/.bin
./terraform version
```

---

## 12. 참고 문서

| 문서 | 내용 |
|------|------|
| [docs/WINDOWS_DEPLOY.md](docs/WINDOWS_DEPLOY.md) | Windows `start.cmd` 설정·과제 목록·배포 |
| [build/README.md](build/README.md) | Terraform 래퍼·setup-aws 상세 설명 |
| [docs/TERRAFORM_GUIDE.md](docs/TERRAFORM_GUIDE.md) | 2023 WSI 과제 아키텍처·요구사항 매핑 |
| [Terraform 공식 문서](https://developer.hashicorp.com/terraform/docs) | 공식 레퍼런스 |
| [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) | AWS 리소스 문서 |

---

## 하루 작업 루틴 (요약)

```bash
# 1. 시작
cd korean_skills_2026
git switch dev && git pull

# 2. AWS 키 (최초 1회 또는 키 변경 시)
./setup-aws          # Mac/Linux
.\setup-aws.cmd      # Windows

# 3. 과제 폴더에서 Terraform
cd day1
../terraform init
../terraform plan
../terraform apply

# 4. 검증 후 삭제 (연습/테스트 시)
../terraform destroy

# 5. 커밋
cd ..
git add .
git commit -m "feat: day1 과제 완료"
git push origin dev
```

---

**핵심만 기억하세요:**

1. `terraform` 설치 없이 → **`terraform.cmd`** (Windows) / **`./terraform`** (Mac/Linux)
2. AWS 키는 → **`setup-aws`** 한 번만
3. 배포 흐름 → **`init` → `plan` → `apply` → `destroy`**
4. 연습 끝나면 → **`destroy` 필수**
