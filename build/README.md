# build — 별도 설치 없이 Terraform 사용하기

`git clone`만 하면 Terraform을 **choco / winget / brew / apt 설치 없이** 바로 쓸 수 있습니다.

처음 실행할 때 `build/.bin/`에 Terraform이 자동으로 내려받아지고, 이후에는 그 파일을 재사용합니다.

---

## 어떻게 쓰면 되나요?

두 가지 방법이 있습니다. **둘 다 같은 바이너리**를 씁니다.

| 방법 | Windows (권장) | Mac / Linux / Git Bash |
|------|----------------|-------------------------|
| **A. 레포 루트** (더 편함) | `terraform.cmd version` | `./terraform version` |
| **B. build 폴더** | `build\terraform.cmd version` | `./build/terraform version` |

> Windows에서는 **PowerShell** 또는 **명령 프롬프트(CMD)** 에서 `terraform.cmd`를 쓰면 됩니다.  
> `terraform`만 입력하면 시스템에 설치된(또는 없는) 전역 명령이 실행될 수 있으니, **반드시 `terraform.cmd`** 를 사용하세요.

---

## Windows 빠른 시작

### 1. 클론

```powershell
git clone git@github.com:본인username/korean_skills_2026.git
cd korean_skills_2026
```

### 2. 버전 확인 (첫 실행 시 자동 다운로드)

**PowerShell:**

```powershell
.\terraform.cmd version
```

**명령 프롬프트(CMD):**

```cmd
terraform.cmd version
```

### 3. AWS 키 입력 (한 번만)

```powershell
.\setup-aws.cmd
```

Access Key, Secret Key, 리전을 입력하면 `.env`에 저장되고 이후 `terraform.cmd` 실행 시 자동 적용됩니다.

### 4. 과제 폴더에서 작업

```powershell
cd day1
..\terraform.cmd init
..\terraform.cmd plan
..\terraform.cmd apply
```

프로젝트 루트에 있을 때 특정 폴더를 지정하려면:

```powershell
.\terraform.cmd -chdir=day1 init
.\terraform.cmd -chdir=day1 plan
```

---

## Mac / Linux / Git Bash 빠른 시작

```bash
git clone git@github.com:본인username/korean_skills_2026.git
cd korean_skills_2026

./terraform version

./setup-aws    # AWS 키 입력 (최초 1회)

cd day1
../terraform init
../terraform plan
```

---

## 필요한 것 / 필요 없는 것

| 항목 | Windows | Mac / Linux |
|------|---------|-------------|
| Terraform 별도 설치 | ❌ | ❌ |
| 인터넷 (최초 1회) | ✅ | ✅ |
| PowerShell 5+ (Windows 기본 내장) | ✅ | — |
| `curl` + `unzip` (Git Bash 등) | Git Bash 사용 시 | ✅ |
| AWS 자격 증명 (`apply` 시) | ✅ | ✅ |

---

## Terraform이란?

**Terraform**은 AWS 같은 클라우드 자원을 **코드(.tf 파일)** 로 만들고 관리하는 도구입니다.

| 단계 | 명령 | 비유 |
|------|------|------|
| 초기화 | `init` | 도구·플러그인 준비 |
| 미리보기 | `plan` | 설계도 확인 |
| 배포 | `apply` | 실제 공사 |
| 삭제 | `destroy` | 철거 |

---

## 자주 쓰는 명령어

과제 폴더(`.tf` 파일이 있는 곳)에서 실행하세요.

### Windows (PowerShell)

```powershell
# 과제 폴더 안에서
..\terraform.cmd init
..\terraform.cmd plan
..\terraform.cmd apply
..\terraform.cmd destroy
..\terraform.cmd validate
..\terraform.cmd output
```

### Mac / Linux

```bash
../terraform init
../terraform plan
../terraform apply
```

`apply` / `destroy`는 확인 프롬프트가 뜹니다. 자동 승인은 `-auto-approve` (주의해서 사용).

---

## AWS 자격 증명 설정

### 방법 A — setup-aws (권장)

대화형으로 입력하면 `.env`에 저장되고, `terraform` 실행 시 자동 적용됩니다.

```powershell
# Windows
.\setup-aws.cmd

# Mac / Linux
./setup-aws
```

입력 항목:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION` (Enter만 누르면 `ap-northeast-2`)

### 방법 B — .env.example 복사

```bash
cp .env.example .env
# .env 파일을 직접 편집
```

### 방법 C — 수동 환경 변수 (임시)

`.env` 없이 현재 터미널 세션에만 적용할 때:

**Windows (PowerShell):**

```powershell
$env:AWS_ACCESS_KEY_ID = "AKIA..."
$env:AWS_SECRET_ACCESS_KEY = "..."
$env:AWS_DEFAULT_REGION = "ap-northeast-2"
```

**Mac / Linux:**

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="ap-northeast-2"
```

> `*.tfvars`, `.env` 모두 `.gitignore`에 포함되어 있습니다.

---

## 폴더 구조

```
korean_skills_2026/
├── terraform.cmd       ← Windows CMD용 (루트에서 바로 실행)
├── terraform.ps1       ← Windows PowerShell용
├── terraform           ← Mac/Linux/Git Bash용
├── setup-aws.cmd       ← AWS 키 입력 (Windows)
├── setup-aws           ← AWS 키 입력 (Mac/Linux)
├── .env.example        ← 템플릿 (복사해서 .env 로 사용 가능)
└── build/
    ├── README.md       ← 이 문서
    ├── VERSION         ← Terraform 버전 (현재 1.9.8)
    ├── terraform.cmd   ← Windows 실제 로직 진입점
    ├── terraform.ps1   ← 다운로드 + 실행 (Windows)
    ├── terraform       ← 다운로드 + 실행 (Unix/Git Bash)
    └── .bin/           ← 자동 생성 (Git 제외)
        └── terraform.exe   (Windows)
        └── terraform         (Mac/Linux)
```

**루트의 `terraform.cmd` / `terraform`은 `build/` 안 스크립트를 호출하는 짧은 래퍼**입니다.  
실제 다운로드 로직은 `build/`에만 있습니다.

---

## 동작 원리

1. `terraform.cmd`(Windows) 또는 `./terraform`(Unix) 실행
2. `build/.bin/`에 실행 파일이 없으면 HashiCorp에서 **Terraform 1.9.8** 다운로드
3. OS·CPU에 맞는 zip 선택 (Windows / Linux / macOS, amd64 / arm64)
4. 받은 인자를 그대로 Terraform에 전달

PC마다 Terraform을 설치할 필요 없이, **이 레포 안에서만** 독립적으로 동작합니다.

---

## build 폴더 vs 레포 루트 — 뭐가 더 나은가?

| | build만 쓸 때 | 루트 래퍼 추가 (현재 구조) |
|--|--------------|---------------------------|
| 명령 길이 | `build\terraform.cmd init` | `terraform.cmd init` |
| 역할 분리 | 도구는 build, 과제는 day* | 동일 (도구 코드는 여전히 build/) |
| 추천 | — | **Windows 사용자에게 더 편함** |

**결론:** 다운로드·버전 관리는 `build/`에 두고, 루트에는 얇은 래퍼만 두는 방식이 가장 깔끔합니다.  
clone 후 바로 `terraform.cmd init`처럼 쓸 수 있으면서, `build/` 폴더 목적도 유지됩니다.

---

## 자주 하는 실수

### Windows: `terraform`은 안 되고 `terraform.cmd`만 된다

```powershell
# ❌ 시스템 전역 terraform (없으면 오류)
terraform init

# ✅ 이 레포의 래퍼
.\terraform.cmd init
```

### Mac/Linux: `./` 빼먹기

```bash
# ❌
terraform init

# ✅
./terraform init
```

### `Error: No valid credential sources found`

AWS 키가 없습니다. 위 [AWS 자격 증명 설정](#aws-자격-증명-설정) 참고.

### PowerShell 실행 정책 오류

`terraform.cmd`는 `-ExecutionPolicy Bypass`로 실행하므로 보통 문제없습니다.  
직접 `.ps1`을 실행할 때만 정책 오류가 날 수 있습니다. 이 경우 `terraform.cmd`를 쓰세요.

### 다운로드 실패

- 인터넷 연결 확인
- `releases.hashicorp.com` 접근 가능 여부 확인 (학교·회사 방화벽)

---

## 버전 변경

`build/VERSION` 파일의 숫자를 바꾼 뒤, 기존 바이너리를 삭제하고 다시 실행하세요.

**Windows:**

```powershell
Remove-Item -Recurse -Force build\.bin
.\terraform.cmd version
```

**Mac / Linux:**

```bash
rm -rf build/.bin
./terraform version
```

---

## 더 자세한 내용

과제별 아키텍처·요구사항은 `docs/TERRAFORM_GUIDE.md`를 참고하세요.
