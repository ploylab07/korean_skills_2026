import base64
import json
import logging
import os
from datetime import datetime, timezone

import boto3
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
from kafka import KafkaProducer
from kafka.oauth.abstract import AbstractTokenProvider

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DDB_TABLE = os.environ["DDB_TABLE"]
ALERT_TOPIC = os.environ["ALERT_TOPIC"]
BOOTSTRAP_SERVER = os.environ["BOOTSTRAP_SERVER"]
REGION = os.environ.get("AWS_REGION", "ap-northeast-1")

ddb = boto3.resource("dynamodb")
table = ddb.Table(DDB_TABLE)

_producer = None


class MSKTokenProvider(AbstractTokenProvider):
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
        return token


def get_producer():
    global _producer
    if _producer is None:
        servers = [s.strip() for s in BOOTSTRAP_SERVER.split(",") if s.strip()]
        _producer = KafkaProducer(
            bootstrap_servers=servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="OAUTHBEARER",
            sasl_oauth_token_provider=MSKTokenProvider(),
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        )
    return _producer


def now_log_prefix():
    return datetime.now(timezone.utc).strftime("%Y/%m/%d %H:%M:%S")


def evaluate(data):
    temp = float(data["temperature"])
    humidity = float(data["humidity"])
    if temp > 80:
        return "ALERT", f"Temperature exceeded threshold: {temp}°C"
    if temp < 10:
        return "ALERT", f"Temperature below threshold: {temp}°C"
    if humidity > 90:
        return "ALERT", f"Humidity exceeded threshold: {humidity}%"
    if humidity < 20:
        return "ALERT", f"Humidity below threshold: {humidity}%"
    return "NORMAL", None


def handler(event, context):
    records = []
    for msgs in event.get("records", {}).values():
        records.extend(msgs)

    logger.info("%s Processing batch: %d messages", now_log_prefix(), len(records))

    producer = get_producer()

    for record in records:
        payload = json.loads(base64.b64decode(record["value"]).decode("utf-8"))
        sensor_id = payload.get("sensorId", "UNKNOWN")
        temp = float(payload["temperature"])
        humidity = float(payload["humidity"])
        status, reason = evaluate(payload)

        if status == "NORMAL":
            table.put_item(
                Item={
                    "sensorId": sensor_id,
                    "timestamp": payload["timestamp"],
                    "temperature": str(payload["temperature"]),
                    "humidity": str(payload["humidity"]),
                    "location": payload.get("location", ""),
                    "status": "NORMAL",
                }
            )
            logger.info(
                "%s %s: NORMAL - temp=%s°C, humidity=%s%%",
                now_log_prefix(),
                sensor_id,
                temp,
                humidity,
            )
        else:
            alert_payload = dict(payload)
            alert_payload["status"] = "ALERT"
            alert_payload["alert_reason"] = reason
            producer.send(ALERT_TOPIC, value=alert_payload)
            short_reason = reason.split(":")[0] if reason else "ALERT"
            logger.info(
                "%s %s: ALERT - temp=%s°C (%s)",
                now_log_prefix(),
                sensor_id,
                temp,
                short_reason,
            )

    producer.flush()
    return {"processed": len(records)}
