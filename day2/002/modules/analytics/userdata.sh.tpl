#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

dnf install -y python3.12 python3.12-pip
install -d -m 0755 /opt/app
echo '${app_py_b64}' | base64 -d > /opt/app/app.py
echo '${requirements_b64}' | base64 -d > /opt/app/requirements.txt

python3.12 -m pip install --upgrade pip
python3.12 -m pip install -r /opt/app/requirements.txt

cat > /etc/systemd/system/app.service <<'UNIT'
[Unit]
Description=Analytics Flask App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=STREAM_NAME=wsc2026-order-stream
Environment=AWS_REGION=${region}
WorkingDirectory=/opt/app
ExecStart=/usr/bin/python3.12 -m gunicorn -b 0.0.0.0:5000 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now app
