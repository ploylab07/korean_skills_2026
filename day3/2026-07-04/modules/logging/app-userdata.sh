#!/bin/bash
set -euxo pipefail

timedatectl set-timezone Asia/Seoul

dnf install -y docker fluent-bit
systemctl enable --now docker

mkdir -p /app
cat > /app/app.py <<'APP_EOF'
${app_py}
APP_EOF

cat > /app/requirements.txt <<'REQ_EOF'
${requirements_txt}
REQ_EOF

cat > /app/Dockerfile <<'DOCKER_EOF'
${dockerfile}
DOCKER_EOF

cd /app
docker build -t wsc-log-app:latest .
docker rm -f wsc-log-app 2>/dev/null || true
docker run -d --name wsc-log-app --restart=always \
  --log-driver=json-file \
  -p 5000:5000 \
  wsc-log-app:latest

mkdir -p /etc/fluent-bit
cat > /etc/fluent-bit/fluent-bit.conf <<FB_EOF
[SERVICE]
    Flush        1
    Daemon       Off
    Log_Level    info
    Parsers_File parsers.conf

[INPUT]
    Name              tail
    Path              /var/lib/docker/containers/*/*-json.log
    Parser            docker
    Tag               docker.*
    Refresh_Interval  5

[FILTER]
    Name          record_modifier
    Match         *
    Record        namespace wsc-app-log

[OUTPUT]
    Name          loki
    Match         *
    Host          ${loki_host}
    Port          3100
    Uri           /loki/api/v1/push
    Labels        {namespace="wsc-app-log"}
    line_format   json
FB_EOF

cat > /etc/fluent-bit/parsers.conf <<'PARSER_EOF'
[PARSER]
    Name        docker
    Format      json
    Time_Key    time
    Time_Format %Y-%m-%dT%H:%M:%S.%L
    Time_Keep   On
PARSER_EOF

systemctl enable --now fluent-bit

# Loki NLB가 준비될 때까지 재시도
for i in $(seq 1 60); do
  if curl -sf "http://${loki_host}:3100/ready" >/dev/null 2>&1; then
    systemctl restart fluent-bit
    break
  fi
  sleep 10
done
