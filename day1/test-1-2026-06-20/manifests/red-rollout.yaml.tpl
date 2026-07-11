apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: red-rollout
  namespace: skills
spec:
  replicas: 2
  strategy:
    blueGreen:
      activeService: red-active
      previewService: red-preview
      autoPromotionEnabled: true
  selector:
    matchLabels:
      app: red
  template:
    metadata:
      labels:
        app: red
    spec:
      nodeSelector:
        role: app
      tolerations:
        - key: app
          operator: Equal
          value: "true"
          effect: NoSchedule
      containers:
        - name: red
          image: ${IMAGE_RED}
          ports:
            - containerPort: 8080
          envFrom:
            - secretRef:
                name: db-secret
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: red-active
  namespace: skills
spec:
  selector:
    app: red
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: red-preview
  namespace: skills
spec:
  selector:
    app: red
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: red-tgb
  namespace: skills
spec:
  serviceRef:
    name: red-active
    port: 8080
  targetGroupARN: ${TG_RED}
  targetType: ip
