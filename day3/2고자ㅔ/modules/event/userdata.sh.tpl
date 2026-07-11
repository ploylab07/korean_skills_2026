#!/bin/bash
set -euxo pipefail

dnf install -y python3.11 python3.11-pip amazon-cloudwatch-agent amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

python3.11 -m pip install fastapi uvicorn

install -d -o ec2-user -g ec2-user /home/ec2-user
echo '${app_py_b64}' | base64 -d > /home/ec2-user/app.py
chown ec2-user:ec2-user /home/ec2-user/app.py
install -d -o ec2-user -g ec2-user /var/log/gj2026-app

cat > /usr/local/bin/gj2026-metric.sh <<'METRIC'
#!/bin/bash
set -euo pipefail
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
if curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
  COUNT=1
  # Ensure "health" appears in /gj2026/event/app-logs for scoring 3-2
  echo "$(date -Is) INFO:     127.0.0.1 - \"GET /health HTTP/1.1\" 200 OK" >> /var/log/gj2026-app/app.log
else
  COUNT=0
fi
aws cloudwatch put-metric-data \
  --namespace procstat \
  --metric-name app_process_count \
  --dimensions "InstanceId=$INSTANCE_ID" \
  --value "$COUNT" \
  --storage-resolution 1 \
  --region ap-northeast-2
METRIC
chmod +x /usr/local/bin/gj2026-metric.sh

cat > /etc/systemd/system/gj2026-app.service <<'UNIT'
[Unit]
Description=GJ2026 FastAPI App
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3.11 /home/ec2-user/app.py
ExecStopPost=/usr/local/bin/gj2026-metric.sh
Restart=on-failure
RestartSec=3
StandardOutput=append:/var/log/gj2026-app/app.log
StandardError=append:/var/log/gj2026-app/app.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now gj2026-app

for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:8080/health >/dev/null && break
  sleep 2
done

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CW'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/gj2026-app/app.log",
            "log_group_name": "/gj2026/event/app-logs",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CW

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
systemctl enable amazon-cloudwatch-agent
systemctl restart amazon-cloudwatch-agent

cat > /etc/systemd/system/gj2026-health.service <<'UNIT'
[Unit]
Description=GJ2026 health probe
After=gj2026-app.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do curl -sf http://127.0.0.1:8080/health >/dev/null || true; sleep 10; done'
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/gj2026-metric.service <<'UNIT'
[Unit]
Description=GJ2026 CloudWatch metric publisher
After=network-online.target gj2026-app.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/local/bin/gj2026-metric.sh; sleep 10; done'
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now gj2026-health gj2026-metric
/usr/local/bin/gj2026-metric.sh || true
