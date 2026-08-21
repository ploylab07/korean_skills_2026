#!/usr/bin/env bash
# Post-apply: images, k8s, targets, NP, mark.sh vars
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export AWS_DEFAULT_REGION=ap-northeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER=gj2026-eks-cluster
ECR="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
BOOK_IMAGE="${ECR}/book:latest"

echo "== kubeconfig =="
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_DEFAULT_REGION" --alias gj2026
kubectl config use-context gj2026

echo "== authenticator can read aws-auth (CONFIG_MAP / API_AND_CONFIG_MAP) =="
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: eks-authenticator-aws-auth
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["aws-auth"]
    verbs: ["get", "watch", "list"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: eks-authenticator-aws-auth
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: eks-authenticator-aws-auth
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: eks:authenticator
EOF

echo "== approve kubelet-serving CSRs (custom hostnames) =="
for i in $(seq 1 12); do
  pending=$(kubectl get csr --no-headers 2>/dev/null | awk '$NF !~ /Issued/ {print $1}')
  for c in $pending; do
    [ -n "$c" ] && kubectl certificate approve "$c" >/dev/null 2>&1 || true
  done
  issued=$(kubectl get csr --no-headers 2>/dev/null | grep -c Issued || true)
  [ "${issued:-0}" -ge 4 ] && break
  sleep 5
done

echo "== scrub EC2_LINUX access entries on node roles (keep aws-auth usernames) =="
for arn in \
  "arn:aws:iam::${ACCOUNT_ID}:role/gj2026-eks-addon-node-role" \
  "arn:aws:iam::${ACCOUNT_ID}:role/gj2026-eks-app-node-role"; do
  aws eks delete-access-entry --cluster-name "$CLUSTER" --principal-arn "$arn" 2>/dev/null || true
done

echo "== ECR login & pull-through =="
aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR"
aws ecr create-pull-through-cache-rule --ecr-repository-prefix ecr-public --upstream-registry-url public.ecr.aws 2>/dev/null || true

echo "== build/push hostname-bootstrap =="
docker build -t hostname-bootstrap:latest bootstrap/
docker tag hostname-bootstrap:latest "${ECR}/hostname-bootstrap:latest"
docker push "${ECR}/hostname-bootstrap:latest"

echo "== build/push book (latest only first) =="
chmod +x book-linux-amd64_v1.0.1 build-push-image.sh
docker build -t book:latest .
docker tag book:latest "$BOOK_IMAGE"
docker push "$BOOK_IMAGE"
# optional second tag after latest is first
MANIFEST=$(aws ecr batch-get-image --repository-name book --image-ids imageTag=latest --query 'images[0].imageManifest' --output text)
aws ecr put-image --repository-name book --image-tag v1.0.0 --image-manifest "$MANIFEST" >/dev/null 2>&1 || true
# If tag order wrong for mark query, drop v1.0.0
TAGS=$(aws ecr describe-images --repository-name book --query 'imageDetails[?contains(imageTags, `latest`)].imageTags|[0]' --output json)
echo "tags=$TAGS"
if ! aws ecr describe-images --repository-name book --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text | grep -q '[0-9]'; then
  aws ecr batch-delete-image --repository-name book --image-ids imageTag=v1.0.0 >/dev/null || true
fi
SIZE=$(aws ecr describe-images --repository-name book --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text)
echo "latest size bytes=$SIZE mb=$(awk "BEGIN{printf \"%.2f\", $SIZE/1024/1024}")"

echo "== grafana image =="
aws ecr create-repository --repository-name grafana 2>/dev/null || true
docker pull grafana/grafana:10.4.2
docker tag grafana/grafana:10.4.2 "${ECR}/grafana:10.4.2"
docker push "${ECR}/grafana:10.4.2"
docker pull "${ECR}/ecr-public/aws-observability/aws-for-fluent-bit:stable" || true
docker pull "${ECR}/ecr-public/nginx/nginx:latest" || true

echo "== wait nodes =="
for i in $(seq 1 60); do
  ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
  echo "ready=$ready"
  [ "$ready" -ge 4 ] && break
  sleep 15
done

echo "== enable network policy on vpc-cni =="
aws eks update-addon --cluster-name "$CLUSTER" --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy":"true"}' \
  --resolve-conflicts OVERWRITE >/dev/null || true
kubectl set env ds/aws-node -n kube-system ENABLE_NETWORK_POLICY=true 2>/dev/null || true

echo "== apply k8s =="
sed "s|IMAGE_PLACEHOLDER|${BOOK_IMAGE}|g" k8s/book.yaml | kubectl apply -f -
# fluent-bit with account ECR
sed "s|IMAGE_ECR|${ECR}|g" k8s/fluentbit.yaml | kubectl apply -f -
# CSR auto-approve for custom hostname kubelet-serving certs (RBAC; approve loop above)
kubectl apply -f k8s/csr-approver.yaml

# WSI Dashboard + CloudWatch datasource provisioning
kubectl -n monitoring create configmap wsi-dashboard \
  --from-file=wsi-dashboard.json=k8s/dashboards/wsi-dashboard.json \
  -o yaml --dry-run=client | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: CloudWatch
        type: cloudwatch
        access: proxy
        uid: cloudwatch
        jsonData:
          authType: default
          defaultRegion: ap-northeast-2
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-provider
  namespace: monitoring
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
      - name: wsi
        orgId: 1
        folder: ""
        type: file
        options:
          path: /var/lib/grafana/dashboards
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      nodeSelector:
        role: addon
      containers:
        - name: grafana
          image: ${ECR}/grafana:10.4.2
          ports:
            - containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_USER
              value: admin
            - name: GF_SECURITY_ADMIN_PASSWORD
              value: "Skills53#"
            - name: GF_SERVER_ROOT_URL
              value: "%(protocol)s://%(domain)s/grafana"
            - name: GF_SERVER_SERVE_FROM_SUB_PATH
              value: "true"
            - name: GF_PATHS_PROVISIONING
              value: /etc/grafana/provisioning
          volumeMounts:
            - name: datasources
              mountPath: /etc/grafana/provisioning/datasources
            - name: dashboards-provider
              mountPath: /etc/grafana/provisioning/dashboards
            - name: dashboards
              mountPath: /var/lib/grafana/dashboards
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 10
      volumes:
        - name: datasources
          configMap:
            name: grafana-datasources
        - name: dashboards-provider
          configMap:
            name: grafana-dashboards-provider
        - name: dashboards
          configMap:
            name: wsi-dashboard
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000
EOF

kubectl -n skills rollout status deploy/book --timeout=300s
kubectl -n monitoring rollout status deploy/grafana --timeout=300s || true

echo "== register ALB targets =="
TG=$(aws elbv2 describe-target-groups --names gj2026-book-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
GTG=$(aws elbv2 describe-target-groups --names gj2026-grafana-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
for ip in $(kubectl -n skills get pods -l app=book -o jsonpath='{.items[*].status.podIP}'); do
  aws elbv2 register-targets --target-group-arn "$TG" --targets Id="$ip",Port=8080
  echo "book $ip"
done
for ip in $(kubectl -n monitoring get pods -l app=grafana -o jsonpath='{.items[*].status.podIP}'); do
  [ -n "$ip" ] && aws elbv2 register-targets --target-group-arn "$GTG" --targets Id="$ip",Port=3000 && echo "graf $ip"
done

echo "== NetworkPolicy ALB ENI only =="
ALB_IPS=$(aws ec2 describe-network-interfaces --filters Name=description,Values='ELB app/gj2026-alb*' --query 'NetworkInterfaces[].PrivateIpAddress' --output text)
{
  echo 'apiVersion: networking.k8s.io/v1'
  echo 'kind: NetworkPolicy'
  echo 'metadata:'
  echo '  name: book-allow-limited'
  echo '  namespace: skills'
  echo 'spec:'
  echo '  podSelector:'
  echo '    matchLabels:'
  echo '      app: book'
  echo '  policyTypes: [Ingress]'
  echo '  ingress:'
  for ip in $ALB_IPS; do
    echo '    - from:'
    echo '        - ipBlock:'
    echo "            cidr: ${ip}/32"
    echo '      ports:'
    echo '        - protocol: TCP'
    echo '          port: 8080'
  done
} | kubectl apply -f -

echo "== update mark.sh DistributionID =="
CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='gj2026-svc-cf' || Comment=='gj2026-cdn'].Id | [0]" --output text)
if [ -z "$CF_ID" ] || [ "$CF_ID" = "None" ]; then
  CF_ID=$(aws cloudfront list-distributions --query 'DistributionList.Items[0].Id' --output text)
fi
sed -i "s/export DistributionID=.*/export DistributionID=\"${CF_ID}\"/" mark.sh
sed -i 's/export BUCKET=.*/export BUCKET="gj2026-static-006"/' mark.sh
# Don't wipe credentials during our local mark runs
sed -i 's/^rm -rf ~\/.aws/# rm -rf ~\/.aws/' mark.sh
echo "CF_ID=$CF_ID"

echo "== re-approve CSRs after workloads =="
kubectl get csr --no-headers 2>/dev/null | awk '$NF !~ /Issued/ {print $1}' | while read -r c; do
  [ -n "$c" ] && kubectl certificate approve "$c" >/dev/null 2>&1 || true
done

echo "== wait targets healthy =="
for i in $(seq 1 30); do
  h=$(aws elbv2 describe-target-health --target-group-arn "$TG" --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)
  echo "healthy=$h"
  [ "$h" -ge 1 ] && break
  sleep 10
done

CF_DOMAIN=$(aws cloudfront get-distribution --id "$CF_ID" --query 'Distribution.DomainName' --output text)
echo "smoke POST"
curl -s -m 20 -X POST -H 'Content-Type: application/json' \
  -d '{"client_id":"C001","username":"Alice","email":"kim@example.com","concert_name":"Busan2025"}' \
  "https://${CF_DOMAIN}/v1/book" || true
echo
echo "DONE post-deploy"
