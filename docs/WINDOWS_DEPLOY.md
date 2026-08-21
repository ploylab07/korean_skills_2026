# Windows 배포 가이드

대회 PC / Windows에서 **과제 목록을 고르고 AWS에 배포**하는 방법입니다.  
Terraform은 PC에 따로 설치할 필요 없습니다. `.\start.cmd` 한 번이면 설정부터 apply까지 진행합니다.

---

## 1. 사전 준비

| 항목 | 설명 |
|------|------|
| OS | Windows 10/11 (PowerShell 5.0 이상) |
| Git | [git-scm.com](https://git-scm.com/) — Git Bash 포함 설치 권장 |
| 인터넷 | 최초 Terraform·도구 다운로드용 |
| AWS Access Key | IAM에서 Access Key ID / Secret Access Key 발급 |

**과제에 따라 `start.cmd`가 자동으로 맞추는 도구**

| 도구 | 용도 | 비고 |
|------|------|------|
| Terraform | IaC 배포 | `build\.bin`에 자동 다운로드 |
| AWS CLI | CodeBuild 대기 등 | 없으면 winget/MSI로 설치 시도 |
| Git Bash | `local-exec` 스크립트 | Git for Windows에 포함 |
| kubectl | EKS 과제 | 필요 시 `build\.bin`에 다운로드 |

Docker Desktop은 **필수가 아닙니다.** (이미지 빌드는 CodeBuild 사용)

---

## 2. 저장소 받기

PowerShell 또는 CMD에서:

```powershell
git clone https://github.com/ploylab07/korean_skills_2026.git
cd korean_skills_2026
git switch master
git pull
```

> GitHub ZIP을 풀면 폴더명이 `korean_skills_2026-master`가 될 수 있습니다.  
> 가능하면 **`git clone`** 을 쓰세요.

---

## 3. 환경 설정 (AWS 키)

배포 전에 AWS 자격 증명을 `.env`에 넣습니다. **Git에 커밋되지 않습니다.**

### 방법 A — 원클릭 배포 중에 입력 (권장)

`.\start.cmd`를 실행하면 `.env`가 없거나 키가 비어 있으면 자동으로 입력을 요청합니다.

### 방법 B — 미리 설정

```powershell
cd korean_skills_2026
.\setup-aws.cmd
```

입력 예시:

```
AWS_ACCESS_KEY_ID:     AKIA...
AWS_SECRET_ACCESS_KEY: (입력 시 화면에 안 보임)
AWS_DEFAULT_REGION:     ap-northeast-2   ← Enter만 눌러도 됨
```

저장 위치: 프로젝트 루트 `.env`

키를 바꾸려면 같은 명령을 다시 실행하거나, `start.cmd` 실행 중 **Re-enter keys?** 에 `y`를 입력합니다.

수동으로 만들 경우 `.env.example`을 복사해 `.env`로 저장한 뒤 값을 채우면 됩니다.

---

## 4. 배포 실행 (`start.cmd`)

프로젝트 **루트**에서:

```powershell
.\start.cmd
```

진행 순서:

1. PowerShell / 네트워크 확인  
2. Terraform + provider mirror 준비  
3. AWS `.env` 확인 (없으면 입력)  
4. **과제 목록**에서 번호 선택  
5. 배포 모드 선택 후 `init` → `validate` → `plan` → `apply`

### 과제 목록 (메뉴)

화면에 아래처럼 나옵니다.

```
=== Assignments ===
  [1] day1 / 002
  [2] day1 / 003
  [3] day1 / 006
  [4] day1 / 007
  [5] day2 / 002
  [6] day2 / 007
  [7] day2 / 008
  [0] Exit
```

| 번호 | 폴더 | 비고 |
|------|------|------|
| 1 | `day1\002` | EKS / 이미지 빌드(CodeBuild) 등 |
| 2 | `day1\003` | apply 후 `deploy.sh` 자동 실행 (Git Bash 필요) |
| 3 | `day1\006` | |
| 4 | `day1\007` | 관측(모니터링) 스택 포함 — apply 시간이 길 수 있음 |
| 5 | `day2\002` | |
| 6 | `day2\007` | |
| 7 | `day2\008` | |
| 0 | 종료 | |

### 배포 모드

```
=== Deploy mode ===
  [1] Apply only
  [2] Destroy only (cleanup state resources)
  [3] Destroy then Apply (clean redeploy)
```

| 모드 | 언제 쓰나 |
|------|-----------|
| **1 Apply only** | 처음 배포, 또는 이미 깨끗할 때 |
| **2 Destroy only** | 연습 끝 / 리소스만 지울 때 |
| **3 Destroy then Apply** | 이름 충돌·부분 실패 후 **깨끗이 다시** 배포할 때 |

`Continue apply?` / `Continue destroy?` 확인에서 `Y`로 진행합니다.

---

## 5. 배포 후 확인

- 성공 시 마지막에 `=== Deploy finished ===` 가 출력됩니다.  
- 실패 시 `build\last-terraform.log`에 최근 실행 로그가 남습니다.  
- 콘솔에 `Error:` 요약이 보이면 그 내용을 기준으로 원인을 확인하세요.

연습·채점 후에는 **요금 방지를 위해 Destroy(모드 2)** 로 정리하는 것을 권장합니다.

---

## 6. 수동으로 Terraform만 실행할 때

`start.cmd` 대신 특정 과제만 다루려면:

```powershell
cd korean_skills_2026

# 키 (최초 1회)
.\setup-aws.cmd

# 예: day1\002
.\terraform.cmd -chdir=day1\002 init
.\terraform.cmd -chdir=day1\002 plan
.\terraform.cmd -chdir=day1\002 apply
.\terraform.cmd -chdir=day1\002 destroy
```

> Windows에서는 `terraform`이 아니라 **`.\terraform.cmd`** 를 사용하세요.

---

## 7. 자주 발생하는 문제

| 증상 | 대응 |
|------|------|
| PowerShell에서 한글/스크립트 깨짐 | `start.cmd`로 실행 (`chcp 65001` 후 호출). `build\*.ps1`은 UTF-8 BOM |
| `AlreadyExists` / 이름 충돌 | 모드 **[3] Destroy then Apply** |
| AWS 인증 오류 | `.\setup-aws.cmd`로 `.env` 재설정 |
| Git Bash 없음 (day1/003 등) | [Git for Windows](https://git-scm.com/) 재설치 (Bash 포함) |
| apply timeout (모니터링 Helm 등) | 네트워크·이미지 pull 상태 확인 후 모드 3으로 재시도 |
| ZIP으로 받은 폴더 | `git clone`으로 다시 받기 |

---

## 8. 한눈에 보는 흐름

```
git clone → cd korean_skills_2026
        → .\start.cmd
        → (필요 시) AWS 키 입력
        → 과제 번호 선택 (1~7)
        → 배포 모드 선택 (1 Apply / 2 Destroy / 3 Destroy+Apply)
        → 확인 후 배포 완료
```

개발용 검증(`.\verify.cmd`)이나 Cursor 관련 도구는 **대회 현장 배포와 무관**합니다. 현장에서는 **`.\start.cmd`만** 사용하면 됩니다.
