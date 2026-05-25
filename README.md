# Korean Skills 2026

매일 학습 기록을 남기는 저장소입니다.

---

## 📁 폴더 구조

```
korean_skills_2026/
├── day1/        # Day 1 학습 자료
├── day2/        # Day 2 학습 자료
├── day3/        # Day 3 학습 자료
└── README.md
```

---

## 🌿 브랜치 전략

이 저장소는 **두 개의 브랜치**로 운영됩니다.

| 브랜치 | 역할 | 누가 직접 푸시? |
|---|---|---|
| `master` | **안정 버전.** 완성된 결과물만 머지 | ❌ (PR로만) |
| `dev` | **개발/작업 중.** 평소 작업은 여기서 | ✅ |

> 💡 평소엔 항상 `dev`에서 작업하고, 완성됐을 때만 `master`로 옮깁니다.

---

## 🚀 처음 시작하는 사람을 위한 가이드

### 0. 사전 준비

이 저장소를 본인 컴퓨터(또는 서버)에 가져옵니다.

```bash
# 작업 폴더로 이동
cd ~/projects

# 저장소 클론 (SSH 방식)
git clone git@github.com:본인username/korean_skills_2026.git

# 폴더로 진입
cd korean_skills_2026
```

> SSH 키가 GitHub에 등록되어 있어야 합니다. 안 되어 있으면 HTTPS 주소 사용:
> ```
> git clone https://github.com/본인username/korean_skills_2026.git
> ```

---

### 1. 작업 시작 전 — 항상 `dev` 브랜치로

```bash
# 현재 어느 브랜치인지 확인
git branch

# dev 브랜치로 이동
git switch dev

# 원격에서 최신 변경사항 가져오기 (다른 곳에서 작업했을 수도 있으니)
git pull
```

---

### 2. 매일 학습 — 새 파일 만들고 커밋

오늘이 day1이라고 가정:

```bash
# day1 폴더에 새 파일 작성
cd day1

# 예: 학습 노트 작성
nano study.md
# 또는
code study.md
```

작성 끝나면 커밋:

```bash
# 프로젝트 루트로 돌아가기
cd ~/projects/korean_skills_2026

# 변경사항 확인
git status

# 변경사항 전체 추가
git add .

# 커밋 (메시지는 명확하게)
git commit -m "day1: 학습 노트 추가"

# 원격에 푸시
git push
```

---

### 3. 커밋 메시지 규칙 (권장)

| 접두사 | 의미 | 예시 |
|---|---|---|
| `feat:` | 새 기능/내용 추가 | `feat: day1 학습 노트 추가` |
| `fix:` | 버그/오타 수정 | `fix: day2 오타 수정` |
| `docs:` | 문서만 수정 | `docs: README 업데이트` |
| `chore:` | 자잘한 정리 | `chore: 폴더 구조 정리` |
| `refactor:` | 코드 구조 개선 | `refactor: 코드 정리` |

---

### 4. `dev` → `master` 머지 (완성됐을 때만)

day1~day3가 다 완성되어 안정화됐다 싶으면 `master`로 옮깁니다.

```bash
# master로 이동
git switch master

# 최신 master 받아오기
git pull

# dev의 내용을 master로 합치기
git merge dev

# 원격 master에 푸시
git push

# 다시 작업 브랜치로 복귀
git switch dev
```

> 📌 더 안전한 방법: GitHub에서 **Pull Request(PR)** 만들어서 머지. 협업이 익숙해지면 PR 방식을 추천합니다.

---

### 5. 새 브랜치에서 실험하기 (선택)

큰 변경을 해볼 때는 `dev`에서 또 다른 브랜치를 따서 작업:

```bash
# dev에서 새 브랜치 생성 & 이동
git switch dev
git switch -c experiment/new-idea

# 작업 후 커밋
git add .
git commit -m "experiment: 새로운 시도"

# 원격에 푸시
git push -u origin experiment/new-idea

# 마음에 들면 dev로 머지
git switch dev
git merge experiment/new-idea
git push

# 안 쓰는 브랜치 삭제
git branch -d experiment/new-idea
git push origin --delete experiment/new-idea
```

---

## 🛠️ 자주 쓰는 git 명령어 모음

| 명령어 | 설명 |
|---|---|
| `git status` | 지금 어떤 파일이 바뀌었는지 확인 |
| `git diff` | 어디가 어떻게 바뀌었는지 보기 |
| `git log --oneline --graph --all` | 커밋 히스토리 그래프 |
| `git branch` | 로컬 브랜치 목록 |
| `git branch -a` | 원격 포함 모든 브랜치 |
| `git switch <브랜치>` | 브랜치 이동 |
| `git switch -c <새브랜치>` | 새 브랜치 만들고 이동 |
| `git pull` | 원격 변경사항 받아오기 |
| `git push` | 로컬 변경사항 원격에 올리기 |
| `git restore <파일>` | 파일 변경 취소 (커밋 전) |
| `git reset HEAD~1` | 마지막 커밋 취소 (파일은 유지) |

---

## 🤖 Cursor CLI 사용법

`cursor-agent`는 터미널에서 동작하는 AI 코딩 도우미입니다. 채팅으로 명령하면 코드를 읽고, 수정하고, 실행해 줍니다.

### 0. 설치 (한 번만)

```bash
curl https://cursor.com/install -fsS | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
cursor-agent --version
```

### 1. 로그인 (한 번만)

```bash
cursor-agent login
```

→ 터미널에 표시된 URL을 브라우저에서 열고, Cursor 계정으로 로그인한 뒤 코드 입력.

```bash
cursor-agent status
```

→ `Logged in as ...` 메시지 보이면 성공.

---

### 2. 기본 실행 — 대화형 모드

항상 **작업할 프로젝트 폴더 안에서** 실행하세요. 그래야 AI가 그 폴더의 파일들을 컨텍스트로 인식합니다.

```bash
cd ~/projects/korean_skills_2026
cursor-agent
```

프롬프트가 뜨면 자연어로 명령:

```
> day1 폴더에 파이썬 기초 학습용 hello.py 파일 만들어줘
> README.md에 오타 있는지 확인하고 고쳐줘
> day2 폴더의 모든 파이썬 파일을 요약해줘
> 이 프로젝트 구조 설명해줘
```

### 3. 한 번만 묻고 끝내기 (one-shot)

대화형 모드 없이 한 줄로:

```bash
cursor-agent "day1 폴더 안에 있는 파일들 요약해줘"
```

### 4. 이전 대화 이어가기

```bash
cursor-agent --resume
```

이전 세션을 이어서 진행합니다.

### 5. 유용한 명령어 모음

| 명령 | 설명 |
|---|---|
| `cursor-agent` | 대화형 시작 |
| `cursor-agent "질문"` | 한 번 묻고 끝 |
| `cursor-agent --resume` | 이전 세션 재개 |
| `cursor-agent status` | 로그인 상태 확인 |
| `cursor-agent --help` | 전체 도움말 |

### 6. 좋은 프롬프트 작성 팁

| ❌ 안 좋은 예 | ✅ 좋은 예 |
|---|---|
| "코드 짜줘" | "day1 폴더에 사용자 입력을 받아 인사하는 파이썬 스크립트 `hello.py` 만들어줘" |
| "버그 고쳐" | "day2/calc.py에서 0으로 나누면 에러 나는데, 예외처리 추가해줘" |
| "정리해" | "README.md의 폴더 구조 섹션을 day5까지 추가하도록 업데이트해줘" |

**핵심**: 어느 파일/폴더에 무엇을 어떻게 해 달라는지 구체적으로 적기.

---

## 📝 매일의 작업 루틴 예시

```bash
# 1. 작업 시작
cd ~/projects/korean_skills_2026
git switch dev
git pull

# 2. 오늘 학습 폴더로 이동
cd day1

# 3. Cursor와 함께 작업
cursor-agent
# > day1에 알고리즘 학습용 메모 파일 만들어줘
# > 작성한 코드 실행해서 결과 확인해줘
# > 코드에 주석 추가해줘

# 4. 변경사항 커밋
cd ..
git status
git add .
git commit -m "feat: day1 알고리즘 학습 노트 추가"
git push

# 5. 작업 종료
```

---

## 🆘 자주 발생하는 문제

### "Updates were rejected because the remote contains work that you do not have locally"

원격에 내가 모르는 커밋이 있다는 뜻. 먼저 받아온 뒤 푸시:

```bash
git pull
git push
```

### 실수로 `master`에 직접 커밋해버린 경우

```bash
# master에 새 커밋이 있는 상태
git switch dev
git merge master
git switch master
git reset --hard HEAD~1   # master를 한 커밋 되돌리기
git switch dev
```

> ⚠️ 이미 push한 뒤라면 더 복잡해집니다. 그냥 dev에서 작업하는 습관을 들이세요.

### 커밋 메시지 잘못 썼을 때 (push 전)

```bash
git commit --amend -m "새로운 메시지"
```

### 어떤 파일이 어디서 왜 바뀌었는지 모를 때

```bash
git log -p <파일경로>     # 그 파일의 변경 이력
git blame <파일경로>      # 줄별로 누가 언제 마지막 수정했는지
```

---

## 🔗 참고 링크

- Git 공식 문서: https://git-scm.com/book/ko/v2
- GitHub Docs: https://docs.github.com/ko
- Cursor 공식 문서: https://docs.cursor.com

---

## ✍️ 마지막 한마디

처음엔 git 명령어가 어렵게 느껴질 수 있지만, **`status` → `add` → `commit` → `push`** 이 네 단계만 익숙해지면 90%는 끝납니다.

작게 자주 커밋하고, 막히면 README의 자주 발생하는 문제 섹션을 보세요. 그래도 안 풀리면 `cursor-agent`에게 물어보면 됩니다.

화이팅!
