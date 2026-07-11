# 2고자ㅔ 작업 메모 (코드 정리 완료 — apply 전)

작성일: 2026-07-10  
작업 폴더: `day3/2고자ㅔ`  
계정: `163389715563`

## 현재 상태

- AWS 리소스: **전부 삭제됨** (state 0)
- Terraform 코드: **100점용으로 정리 완료** (validate 통과)
- **아직 apply 하지 않음**

## 코드에서 고친 핵심 (만점용)

### 1 CDN
- cache policy `min_ttl=1` (캐시 Hit 유도)
- rotate/request/response + `/images` Edge 연동 유지
- 채점 팁: apply 후 **invalidation → 바로 CDN.sh** (캐시 워밍 전)

### 2 Analytics
- 기존 만점 구성 유지 (Kafka/NLB/Flink/stream_proc)
- 채점은 **Analytics EC2에서** 실행

### 3 Event (핵심 수정)
- `Restart=on-failure` → `systemctl stop` 후 자동 재기동 방지 (3-4)
- health 기반 `procstat/app_process_count` 10초 주기 (3-4 OK→ALARM)
- app-logs에 `GET /health` 문자열 기록 (3-2)
- recovery Lambda:
  - `timeout=300`
  - 복구 전 `sleep(60)` (3-4 ALARM 확인용)
  - 복구 후 health wait
  - `/gj2026/event/recovery` put_log_events **sequence token 처리** (3-8)
- updater: healthy일 때만 SSM 동기화 (3-6)
- `app.py` trailing whitespace 정리 (3-3)

### 4 Keycloak (핵심 수정)
- 전용 VPC (기본 VPC IGW blackhole 회피)
- hostname = `{ip}.sslip.io` (AWS OIDC용) + `hostname-strict=false` (채점 IP 접근용)
- Admin REST로 realm/users/clients/claims 구성
- Terraform **team EC2 제거** → `keycloak.sh` 4-0이 생성
- `null_resource.oidc_and_profiles`:
  - realm ready 대기
  - OIDC thumbprint 실인증서로 갱신
  - `$HOME/.aws/gj2026-keycloak-creds.sh` + profiles 설치
- 로컬 스크립트: `modules/keycloak/gj2026-keycloak-creds.sh` (`scope=openid`)

## apply 후 채점 순서

```bash
cd day3/2고자ㅔ
../../terraform apply -auto-approve

# Keycloak thumbprint/프로필은 null_resource가 처리. 실패 시:
# HOST=$(terraform output -raw keycloak_ec2_public_ip | tr . -).sslip.io
# THUMB=$(openssl s_client -connect $HOST:443 -servername $HOST </dev/null 2>/dev/null | openssl x509 -fingerprint -sha1 -noout | awk -F= '{print tolower($2)}' | tr -d ':')
# aws iam update-open-id-connect-provider-thumbprint --open-id-connect-provider-arn ... --thumbprint-list $THUMB

# 1 CDN: invalidation 직후
aws cloudfront create-invalidation --distribution-id ... --paths '/*'
bash CDN.sh

# 2 Analytics: EC2에서
scp Real-time\ data\ analytics.sh ec2-user@$ANALYTICS_IP:/tmp/
ssh ec2-user@$ANALYTICS_IP 'bash /tmp/Real-time\ data\ analytics.sh'

# 3 Event: EC2에서 (깨끗한 상태)
scp Cloud\ event\ handling.sh ec2-user@$EVENT_IP:/tmp/
ssh ec2-user@$EVENT_IP 'bash /tmp/Cloud\ event\ handling.sh'

# 4 Keycloak: 로컬 (프로필 준비된 상태)
bash keycloak.sh
```

## SSH 키

```bash
../../terraform output -raw ssh_private_key_pem > /tmp/gj2026.pem
chmod 600 /tmp/gj2026.pem
```
