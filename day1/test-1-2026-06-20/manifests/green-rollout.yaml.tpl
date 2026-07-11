apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: green-rollout
  namespace: skills
spec:
  replicas: 2
  strategy:
    blueGreen:
      activeService: green-active
      previewService: green-preview
      autoPromotionEnabled: true
  selector:
    matchLabels:
      app: green
  template:
    metadata:
      labels:
        app: green
    spec:
      nodeSelector:
        role: app
      tolerations:
        - key: app
          operator: Equal
          value: "true"
          effect: NoSchedule
      containers:
        - name: green
          image: ${IMAGE_GREEN}
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
  name: green-active
  namespace: skills
spec:
  selector:
    app: green
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: green-preview
  namespace: skills
spec:
  selector:
    app: green
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: green-tgb
  namespace: skills
spec:
  serviceRef:
    name: green-active
    port: 8080
  targetGroupARN: ${TG_GREEN}
  targetType: ip
