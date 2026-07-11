#!/bin/bash
set -euo pipefail

REGION="ap-northeast-2"
CLUSTER="wsc2026-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_IMAGE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/wsc2026-book-ecr:v1.0.0"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: wsc2026
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: wsc2026-book-sa
  namespace: wsc2026
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: book-config
  namespace: wsc2026
data:
  AWS_REGION: ap-northeast-2
  TABLE_NAME: wsc2026-book-table
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wsc2026-book-deploy
  namespace: wsc2026
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wsc2026-book
  template:
    metadata:
      labels:
        app: wsc2026-book
    spec:
      serviceAccountName: wsc2026-book-sa
      nodeSelector:
        wsc2026/node: application
      tolerations:
      - key: wsc2026/node
        operator: Equal
        value: application
        effect: NoSchedule
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: wsc2026-book
      containers:
      - name: book
        image: ${ECR_IMAGE}
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: book-config
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 250m
            memory: 512Mi
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          failureThreshold: 30
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: wsc2026-book-svc
  namespace: wsc2026
  annotations:
    service.kubernetes.io/topology-aware-hints: auto
spec:
  type: ClusterIP
  internalTrafficPolicy: Local
  selector:
    app: wsc2026-book
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: wsc2026-book-pdb
  namespace: wsc2026
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: wsc2026-book
EOF

# CoreDNS domain change
kubectl -n kube-system get configmap coredns -o yaml | \
  sed 's/cluster\.local/wsc2026.skills.local/g' | \
  kubectl apply -f -

# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$REGION" \
  --set vpcId=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=wsc2026-skills-vpc --query 'Vpcs[0].VpcId' --output text) \
  --wait

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wsc2026-book-ingress
  namespace: wsc2026
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-name: wsc2026-app-alb
    alb.ingress.kubernetes.io/group.name: wsc2026-app-alb
    alb.ingress.kubernetes.io/security-groups: $(aws ec2 describe-security-groups --filters Name=group-name,Values=wsc2026-app-alb-sg --query 'SecurityGroups[0].GroupId' --output text)
    alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /v1/book
        pathType: Prefix
        backend:
          service:
            name: wsc2026-book-svc
            port:
              number: 80
EOF

# Observability stack
FLUENT_BIT_ROLE_ARN=$(aws iam get-role --role-name wsc2026-fluent-bit-role --query 'Role.Arn' --output text)
export FLUENT_BIT_ROLE_ARN
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

GRAFANA_ROLE_ARN=$(aws iam get-role --role-name wsc2026-grafana-role --query 'Role.Arn' --output text)
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace \
  --set grafana.adminPassword='Skills$#$@!' \
  --set grafana.service.type=LoadBalancer \
  --set grafana.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$GRAFANA_ROLE_ARN" \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.nodeSelector."wsc2026/node"=addon \
  --set alertmanager.alertmanagerSpec.nodeSelector."wsc2026/node"=addon \
  --set grafana.nodeSelector."wsc2026/node"=addon \
  --set prometheus-node-exporter.tolerations[0].operator=Exists \
  --wait

kubectl apply -f - <<FBEOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluent-bit
  namespace: observability
  annotations:
    eks.amazonaws.com/role-arn: ${FLUENT_BIT_ROLE_ARN}
  annotations:
    eks.amazonaws.com/role-arn: ${FLUENT_BIT_ROLE_ARN}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: observability
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush        1
        Log_Level    info
        Parsers_File parsers.conf
    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*wsc2026-book*.log
        Parser            docker
        Exclude_Path      *health*
    [FILTER]
        Name    grep
        Match   kube.*
        Exclude log .*\/health.*
    [FILTER]
        Name    parser
        Match   kube.*
        Key_Name log
        Parser  json
        Reserve_Data On
    [OUTPUT]
        Name                cloudwatch_logs
        Match               kube.*
        region              ap-northeast-2
        log_group_name      /wsc2026/application
        log_stream_prefix   book-
        auto_create_group   true
  parsers.conf: |
    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
    [PARSER]
        Name        json
        Format      json
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: observability
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      tolerations:
      - operator: Exists
      containers:
      - name: fluent-bit
        image: public.ecr.aws/aws-observability/aws-for-fluent-bit:stable
        env:
        - name: AWS_REGION
          value: ap-northeast-2
        - name: AWS_STS_REGIONAL_ENDPOINTS
          value: regional
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: config
          mountPath: /fluent-bit/etc/
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: config
        configMap:
          name: fluent-bit-config
FBEOF

echo "Deploy complete"
