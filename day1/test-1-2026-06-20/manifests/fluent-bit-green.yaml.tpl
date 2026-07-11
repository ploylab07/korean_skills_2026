apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: green-fluent-bit
  namespace: amazon-cloudwatch
spec:
  selector:
    matchLabels:
      app: green-fluent-bit
  template:
    metadata:
      labels:
        app: green-fluent-bit
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
            name: green-fluent-bit-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: green-fluent-bit-config
  namespace: amazon-cloudwatch
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush        1
        Log_Level    info
        Parsers_File parsers.conf
    [INPUT]
        Name              tail
        Tag               app.green
        Path              /var/log/containers/*green*.log
        Parser            cri
        DB                /var/log/flb_green.db
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
    [FILTER]
        Name    grep
        Match   app.green
        Regex   log (GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)
    [FILTER]
        Name    grep
        Match   app.green
        Exclude log /health
    [OUTPUT]
        Name                cloudwatch_logs
        Match               app.green
        region              ap-northeast-2
        log_group_name      /gj2025/app/green
        log_stream_name     app-green-logs
        auto_create_group   true
  parsers.conf: |
    [PARSER]
        Name        cri
        Format      regex
        Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
        Time_Keep   On
