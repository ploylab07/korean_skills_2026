#!/bin/bash
set -euxo pipefail

KAFKA_VERSION="3.7.0"
SCALA_VERSION="2.13"

dnf install -y java-17-amazon-corretto-headless python3.11 python3.11-pip python3-pip wget tar gzip

python3 -m pip install kafka-python
python3.11 -m pip install kafka-python

install -d -o ec2-user -g ec2-user /opt/kafka /var/lib/kafka /var/log/kafka /var/log/app /home/ec2-user
useradd -r -s /sbin/nologin kafka 2>/dev/null || true
chown -R kafka:kafka /opt/kafka /var/lib/kafka /var/log/kafka
chown ec2-user:ec2-user /var/log/app

cd /tmp
curl -fsSLO "https://archive.apache.org/dist/kafka/$${KAFKA_VERSION}/kafka_$${SCALA_VERSION}-$${KAFKA_VERSION}.tgz"
tar -xzf "kafka_$${SCALA_VERSION}-$${KAFKA_VERSION}.tgz" -C /opt/kafka --strip-components=1

KAFKA_CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
cat > /opt/kafka/config/kraft/server.properties <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@127.0.0.1:9093
listeners=PLAINTEXT://0.0.0.0:9092,EXTERNAL://0.0.0.0:9094,CONTROLLER://127.0.0.1:9093
advertised.listeners=PLAINTEXT://127.0.0.1:9092,EXTERNAL://${nlb_dns}:9094
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
log.dirs=/var/lib/kafka
num.network.threads=3
num.io.threads=8
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
auto.create.topics.enable=false
EOF

/opt/kafka/bin/kafka-storage.sh format -t "$KAFKA_CLUSTER_ID" -c /opt/kafka/config/kraft/server.properties

cat > /etc/systemd/system/kafka.service <<'UNIT'
[Unit]
Description=Apache Kafka KRaft
After=network.target

[Service]
Type=simple
User=kafka
Environment=JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now kafka
sleep 20

for spec in "order-logs:2" "error-stats:1" "high-latency:1" "anomaly:1"; do
  topic="$${spec%%:*}"
  parts="$${spec##*:}"
  /opt/kafka/bin/kafka-topics.sh --create --bootstrap-server localhost:9092 \
    --topic "$topic" --partitions "$parts" --replication-factor 1
done

echo '${app_py_b64}' | base64 -d > /home/ec2-user/app.py
chown ec2-user:ec2-user /home/ec2-user/app.py

cat > /etc/systemd/system/gj2026-data-app.service <<'UNIT'
[Unit]
Description=GJ2026 data log generator
After=kafka.service

[Service]
Type=oneshot
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/app.py
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

echo '${stream_proc_b64}' | base64 -d > /home/ec2-user/stream_proc.py
chmod +x /home/ec2-user/stream_proc.py
chown ec2-user:ec2-user /home/ec2-user/stream_proc.py

cat > /etc/systemd/system/gj2026-stream-proc.service <<'UNIT'
[Unit]
Description=GJ2026 Kafka stream processor
After=kafka.service
Requires=kafka.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/stream_proc.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now gj2026-stream-proc
