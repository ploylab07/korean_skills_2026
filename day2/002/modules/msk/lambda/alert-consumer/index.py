import base64
import json
import logging
import os
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
S3_BUCKET = os.environ["S3_BUCKET"]

sns = boto3.client("sns")
s3 = boto3.client("s3")


def now_log_prefix():
    return datetime.now(timezone.utc).strftime("%Y/%m/%d %H:%M:%S")


def handler(event, context):
    records = []
    for msgs in event.get("records", {}).values():
        records.extend(msgs)

    logger.info("%s Processing alert batch: %d messages", now_log_prefix(), len(records))

    for record in records:
        data = json.loads(base64.b64decode(record["value"]).decode("utf-8"))
        sensor_id = data.get("sensorId", "UNKNOWN")
        timestamp = data.get("timestamp", datetime.now(timezone.utc).isoformat())
        alert_reason = data.get("alert_reason", "Unknown alert")

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Sensor Alert: {sensor_id}",
            Message=json.dumps(
                {
                    "sensorId": sensor_id,
                    "alert_reason": alert_reason,
                    "timestamp": timestamp,
                    "temperature": data.get("temperature"),
                    "humidity": data.get("humidity"),
                }
            ),
        )

        date_part = timestamp.split("T")[0] if "T" in timestamp else datetime.now(timezone.utc).strftime("%Y-%m-%d")
        ts_safe = timestamp.replace(":", "-")
        key = f"alert/{sensor_id}/{date_part}/{ts_safe}.json"
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=json.dumps(data).encode("utf-8"),
            ContentType="application/json",
        )
        logger.info("%s Stored alert for %s at s3://%s/%s", now_log_prefix(), sensor_id, S3_BUCKET, key)

    return {"processed": len(records)}
