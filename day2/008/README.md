# day2/008 — Small Challenges (Terraform)
#
# Windows:  레포 루트에서 .\start.cmd → [7] day2 / 008
# Linux:    ./terraform -chdir=day2/008 init && ./terraform -chdir=day2/008 apply -auto-approve
#
# 모듈:
# 1) DocumentDB NoSQL     ap-northeast-2
# 2) VPC Lattice          ap-northeast-1
# 3) Cloud Event Handling ap-southeast-1
# 4) EKS+KEDA+Karpenter   us-west-2
#
# 채점: asgmt2_module{1..4}_check.sh
