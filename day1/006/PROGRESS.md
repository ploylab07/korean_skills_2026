# day1/006 진행 메모

## 시뮬레이션 (파일 기반)
- `scripts/simulate-score.sh` — 채점기준 30점 = 100%
- 결과: **30.0 / 30.0 (100%)**

## IaC 반영 요약 (origin/dev 이어서)
- 네트워크: private-only VPC, NAT=0, IGW 유지
- 이름 정합: ALB TG `gj2026-book-tg`, CF `gj2026-cdn`, VPC Origin `gj2026-alb-origin`, WAF `gj2026-waf-acl`, 노드 Name `gj2026-eks-*-node`
- NP: post-deploy가 ALB ENI `/32`만 허용 (4-5 timeout)
- Fluent Bit: AZ별 스트림 `/book-svc/ap-northeast-2a|b` + `remote_addr`
- Grafana: admin/`Skills53#`, **WSI Dashboard**, CloudWatch datasource
- Lambda: EMF `gj2026/BookReservation` / `client_id` + `ALL`
- hostname-bootstrap ECR + Bottlerocket bootstrap

## 실제 apply 시
1. `.env` / `./setup-aws` 후 `terraform apply`
2. `./post-deploy.sh` (이미지·k8s·TG·NP·Grafana)
3. `./run-mark.sh` 또는 `mark.sh`

## 주의
- `.env` / AWS 키 / tfstate 커밋 금지
- Bottlerocket 1.63 `hostname-override-source`는 `private-dns-name` | `instance-id` 만 허용

## 2026-08-21 live mark (30/30)

- EKS: create CONFIG_MAP → aws-auth `system:node:gj2026.{{SessionName}}.{addon|app}.node` + authenticator RBAC; CSR approve; optional upgrade to API_AND_CONFIG_MAP for IAM grader (scrub node EC2_LINUX entries).
- 4-5: ALB ENI /32 NP → `curl: (28) Connection timed out`
- 10-1: Fluent Bit stream = IMDS node AZ (`/book-svc/ap-northeast-2a|b`), not ALB ENI
- 3-3: mark with non-root IAM (resource policy Deny); root bypasses Deny
- Grafana: admin/Skills53# WSI Dashboard + CloudWatch DS
