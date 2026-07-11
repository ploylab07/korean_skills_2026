apiVersion: apps/v1
kind: Deployment
metadata:
  name: wsc-deploy
  namespace: wsc
  labels:
    app: wsc-deploy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wsc-deploy
  template:
    metadata:
      labels:
        app: wsc-deploy
    spec:
      serviceAccountName: wsc-sa
      nodeSelector:
        type: app
      tolerations:
        - key: type
          operator: Equal
          value: app
          effect: NoSchedule
      containers:
        - name: wsc-cnt
          image: ${ECR_IMAGE}
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: wsc-config
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: wsc-svc
  namespace: wsc
spec:
  type: ClusterIP
  selector:
    app: wsc-deploy
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: wsc-tgb
  namespace: wsc
spec:
  serviceRef:
    name: wsc-svc
    port: 8080
  targetGroupARN: ${APP_TG_ARN}
  targetType: ip
