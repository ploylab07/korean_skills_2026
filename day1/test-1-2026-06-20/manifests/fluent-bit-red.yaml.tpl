apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluent-bit
  namespace: amazon-cloudwatch
  annotations:
    eks.amazonaws.com/role-arn: ${FLUENT_BIT_ROLE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: red-fluent-bit-config
  namespace: amazon-cloudwatch
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush        1
        Log_Level    info
        Parsers_File parsers.conf
    [INPUT]
        Name              tail
        Tag               app.red
        Path              /var/log/containers/*red*.log
        Parser            cri
        DB                /var/log/flb_red.db
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
    [FILTER]
        Name    grep
        Match   app.red
        Regex   log (GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)
    [FILTER]
        Name    grep
        Match   app.red
        Exclude log /health
    [OUTPUT]
        Name                cloudwatch_logs
        Match               app.red
        region              ap-northeast-2
        log_group_name      /gj2025/app/red
        log_stream_name     app-red-logs
        auto_create_group   true
  parsers.conf: |
    [PARSER]
        Name        cri
        Format      regex
        Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
        Time_Keep   On
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: red-fluent-bit
  namespace: amazon-cloudwatch
spec:
  selector:
    matchLabels:
      app: red-fluent-bit
  template:
    metadata:
      labels:
        app: red-fluent-bit
    spec:
      serviceAccountName: fluent-bit
      nodeSelector:
        role: app
      tolerations:
        - key: app
          operator: Equal
          value: "true"
          effect: NoSchedule
      containers:
        - name: fluent-bit
          image: ${ECR_REGISTRY}/addon/fluent-bit:2.32.2
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
            name: red-fluent-bit-config
