#!/usr/bin/env python3
import json
import time
from collections import Counter, defaultdict, deque
from datetime import datetime, timezone

from kafka import KafkaConsumer, KafkaProducer

BOOT = "localhost:9092"
consumer = KafkaConsumer(
    "order-logs",
    bootstrap_servers=BOOT,
    group_id="gj2026-stream-proc",
    auto_offset_reset="earliest",
    enable_auto_commit=True,
    consumer_timeout_ms=2000,
    value_deserializer=lambda m: json.loads(m.decode()),
)
producer = KafkaProducer(
    bootstrap_servers=BOOT,
    value_serializer=lambda v: json.dumps(v, default=str).encode(),
)

batch = []
hist = defaultdict(lambda: deque(maxlen=100))


def emit_error_stats(logs):
    if not logs:
        return
    total = len(logs)
    errors = sum(1 for x in logs if x.get("status_code", 0) >= 400)
    avg_lat = round(sum(x.get("latency_ms", 0) for x in logs) / total, 2)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]
    producer.send(
        "error-stats",
        {
            "window_start": now,
            "window_end": now,
            "total_count": total,
            "error_count": errors,
            "error_rate": round(errors / total, 2),
            "avg_latency_ms": avg_lat,
        },
    )


def emit_high_latency(x):
    uid = x["user_id"]
    hist[uid].append(x.get("latency_ms", 0))
    avg = sum(hist[uid]) / len(hist[uid])
    if x.get("latency_ms", 0) > avg:
        producer.send(
            "high-latency",
            {
                "order_id": x["order_id"],
                "user_id": uid,
                "latency_ms": x["latency_ms"],
                "avg_latency_ms": round(avg, 2),
                "proc_time": datetime.now(timezone.utc).isoformat(),
                "is_anomaly": 1 if x.get("latency_ms", 0) > 500 else 0,
            },
        )


def emit_anomalies(logs):
    if not logs:
        return
    users = Counter(x["user_id"] for x in logs)
    for uid, cnt in users.items():
        ulogs = [x for x in logs if x["user_id"] == uid]
        bot = sum(1 for x in ulogs if x.get("cart_age_seconds", 99) < 3)
        rate = sum(1 for x in ulogs if x.get("status_code") == 429)
        atype = "NORMAL"
        if bot / len(ulogs) > 0.8:
            atype = "BOT_SUSPECTED"
        elif rate / len(ulogs) > 0.5:
            atype = "RATE_LIMITED"
        elif cnt > 150:
            atype = "EXCESSIVE_ORDER"
        if atype != "NORMAL":
            now = datetime.now(timezone.utc).isoformat()
            producer.send(
                "anomaly",
                {
                    "user_id": uid,
                    "order_count": cnt,
                    "rate_limit_count": rate,
                    "bot_suspected_count": bot,
                    "anomaly_type": atype,
                    "window_start": now,
                    "window_end": now,
                },
            )


while True:
    chunk = []
    for msg in consumer:
        chunk.append(msg.value)
    if chunk:
        batch.extend(chunk)
        emit_error_stats(chunk)
        for log in chunk:
            emit_high_latency(log)
        emit_anomalies(batch[-500:])
        producer.flush()
        batch = batch[-1000:]
    else:
        time.sleep(1)
