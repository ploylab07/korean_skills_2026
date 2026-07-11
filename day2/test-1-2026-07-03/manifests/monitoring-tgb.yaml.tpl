apiVersion: v1
kind: Service
metadata:
  name: grafana-svc
  namespace: monitoring
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: grafana
  ports:
    - port: 80
      targetPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-svc
  namespace: monitoring
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: prometheus
  ports:
    - port: 9090
      targetPort: 9090
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: grafana-tgb
  namespace: monitoring
spec:
  serviceRef:
    name: grafana-svc
    port: 80
  targetGroupARN: ${GRAFANA_TG_ARN}
  targetType: ip
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: prometheus-tgb
  namespace: monitoring
spec:
  serviceRef:
    name: prometheus-svc
    port: 9090
  targetGroupARN: ${PROM_TG_ARN}
  targetType: ip
