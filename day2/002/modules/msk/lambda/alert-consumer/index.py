import base64
import json
import os
from datetime import datetime, timezone

import boto3

sns = boto3.client("sns")
s3 = boto3.client("s3")


def handler(event, _context):
    processed = 0
    for records in event.get("records", {}).values():
        for record in records:
            data = json.loads(base64.b64decode(record["value"]).decode("utf-8"))
            sensor_id = str(data.get("sensorId", "UNKNOWN"))
            timestamp = str(data.get("timestamp", datetime.now(timezone.utc).isoformat()))
            sns.publish(
                TopicArn=os.environ["SNS_TOPIC_ARN"],
                Subject=f"Sensor Alert: {sensor_id}",
                Message=json.dumps(data),
            )
            date = timestamp.split("T", 1)[0]
            key = f"alert/{sensor_id}/{date}/{timestamp.replace(':', '-')}.json"
            s3.put_object(
                Bucket=os.environ["S3_BUCKET"],
                Key=key,
                Body=json.dumps(data).encode("utf-8"),
                ContentType="application/json",
            )
            processed += 1
    return {"processed": processed}
