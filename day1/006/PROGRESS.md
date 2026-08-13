# day1/006 진행 메모 (새 계정 851725644999)

## 완료된 것
- Terraform apply로 VPC/EKS/ALB/CF/S3/DDB/Lambda 등 기본 스택 생성
- book 이미지(~2.54MB) ECR push, post-deploy로 book/grafana/fluent-bit 배포
- 노드 이름 `gj2026.<iid>.{addon|app}.node` 형식은 Bottlerocket hostname-override + bootstrap으로 설정 가능
- mark 1회: 4-3 노드명 통과, POST/405/403/예약 API 통과

## 남은 이슈 (중단 시점)
1. **노드 인증/CSR**: 커스텀 hostname과 `system:node:{{EC2PrivateDNSName}}` 불일치 → kubelet serving CSR 미발급·exec TLS 오류
2. **해결 방향**: addon/app 각각 전용 IAM 역할 + aws-auth username `system:node:gj2026.{{SessionName}}.{addon|app}.node`
3. NetworkPolicy(4-5 timeout), Fluent Bit JSON(10-1), NAT 계정 오염(1-3) 재검증 필요
4. 100점 후 terraform destroy + Windows 명령 검증

## 주의
- `.env` / AWS 키 / tfstate 커밋 금지
- Bottlerocket 1.63 `hostname-override-source`는 `private-dns-name` | `instance-id` 만 허용 (`userdata` 불가)
