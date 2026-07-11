apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: logging
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush        1
        Log_Level    info
        Parsers_File parsers.conf

    [INPUT]
        Name              tail
        Tag               app.*
        Path              /var/log/containers/wsc-cnt*.log
        Parser            docker
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On

    [FILTER]
        Name    grep
        Match   app.*
        Exclude log /health

    [OUTPUT]
        Name                cloudwatch_logs
        Match               app.*
        region              ${REGION}
        log_group_name      ${LOG_GROUP}
        log_stream_name     /wsc/app/log
        auto_create_group   false

  parsers.conf: |
    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
        Time_Keep   On
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
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
      nodeSelector:
        type: app
      tolerations:
        - key: type
          operator: Equal
          value: app
          effect: NoSchedule
      containers:
        - name: fluent-bit
          image: public.ecr.aws/aws-observability/aws-for-fluent-bit:2.32.2
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
