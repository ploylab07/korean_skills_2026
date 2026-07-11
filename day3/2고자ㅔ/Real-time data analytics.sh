#!/bin/bash

echo =====2-1=====
for topic in order-logs error-stats high-latency anomaly; do
    partitions=$(/opt/kafka/bin/kafka-topics.sh --describe --topic $topic --bootstrap-server localhost:9092 \
        | grep -oP "PartitionCount:\s*\K[0-9]+")
    echo "$topic PartitionCount: $partitions"
done
echo

echo =====2-2=====
for topic in error-stats high-latency anomaly; do
    /opt/kafka/bin/kafka-topics.sh --delete --topic $topic --bootstrap-server localhost:9092
    /opt/kafka/bin/kafka-topics.sh --create --topic $topic --bootstrap-server localhost:9092 \
        --partitions 1 --replication-factor 1
done
HASH=$(sha256sum /home/ec2-user/app.py | cut -d' ' -f1)
EXPECTED="cdb45383d813e8df2cdd412da6d35139f74b043a7c482c6214430bddde654273"
[ "$HASH" = "$EXPECTED" ] && echo "일치" || echo "불일치"
python3 /home/ec2-user/app.py
wc -l /var/log/app/orders.log
/opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server localhost:9092 \
    --topic order-logs --time -1 \
    | awk -F: '{sum += $NF} END {print "Total Kafka records: " sum}'
aws elbv2 describe-load-balancers \
    --names gj2026-data-nlb \
    --query 'LoadBalancers[0].[LoadBalancerName,State.Code]' \
    --output text
echo

sleep 30

echo =====2-3=====
/opt/kafka/bin/kafka-console-consumer.sh --topic error-stats --partition 0 --bootstrap-server localhost:9092 --max-messages 1 --offset 0 2>/dev/null
echo

echo =====2-4=====
/opt/kafka/bin/kafka-console-consumer.sh --topic high-latency --partition 0 --bootstrap-server localhost:9092 --max-messages 1 --offset 0 2>/dev/null
echo

echo =====2-5=====
/opt/kafka/bin/kafka-console-consumer.sh --topic anomaly --partition 0 \
  --bootstrap-server localhost:9092 --max-messages 1 --offset 0 2>/dev/null
echo
