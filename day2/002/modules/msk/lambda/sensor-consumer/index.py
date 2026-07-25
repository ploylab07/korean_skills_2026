import base64
import json
import logging
import os

import boto3
from kafka import KafkaProducer

logger = logging.getLogger()
logger.setLevel(logging.INFO)

table = boto3.resource("dynamodb").Table(os.environ["DDB_TABLE"])
_producer = None


def producer():
    global _producer
    if _producer is None:
        _producer = KafkaProducer(
            bootstrap_servers=os.environ["BOOTSTRAP_SERVER"].split(","),
            security_protocol="PLAINTEXT",
            value_serializer=lambda value: json.dumps(value).encode("utf-8"),
        )
    return _producer


def alert_reason(data):
    temperature = float(data["temperature"])
    humidity = float(data["humidity"])
    if temperature > 80:
        return f"Temperature exceeded threshold: {temperature}°C"
    if temperature < 10:
        return f"Temperature below threshold: {temperature}°C"
    if humidity > 90:
        return f"Humidity exceeded threshold: {humidity}%"
    if humidity < 20:
        return f"Humidity below threshold: {humidity}%"
    return None


def handler(event, _context):
    processed = 0
    for records in event.get("records", {}).values():
        for record in records:
            data = json.loads(base64.b64decode(record["value"]).decode("utf-8"))
            reason = alert_reason(data)
            if reason is None:
                table.put_item(Item={
                    "sensorId": str(data["sensorId"]),
                    "timestamp": str(data["timestamp"]),
                    "temperature": str(data["temperature"]),
                    "humidity": str(data["humidity"]),
                    "location": str(data.get("location", "")),
                    "status": "NORMAL",
                })
            else:
                data["status"] = "ALERT"
                data["alert_reason"] = reason
                producer().send(os.environ["ALERT_TOPIC"], value=data)
            processed += 1

    if _producer is not None:
        _producer.flush()
    return {"processed": processed}
