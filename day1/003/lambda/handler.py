import json
import os
from collections import OrderedDict
from datetime import datetime, timezone, timedelta

import boto3

TABLE_NAME = os.environ.get("TABLE_NAME", "wsc2026-book-table")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

KST = timezone(timedelta(hours=9))


def _format_created_at(value):
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        dt = datetime.fromtimestamp(value, tz=KST)
    else:
        text = str(value)
        try:
            if text.endswith("Z"):
                dt = datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(KST)
            elif "+" in text or text.endswith("KST"):
                dt = datetime.fromisoformat(text.replace(" KST", "+09:00")).astimezone(KST)
            else:
                dt = datetime.fromisoformat(text).replace(tzinfo=KST)
        except ValueError:
            return text
    return dt.strftime("%Y-%m-%d %H:%M:%S KST")


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    booking_id = params.get("booking_id")
    if not booking_id:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "booking_id is required"}),
        }

    response = table.query(
        IndexName="booking_id-index",
        KeyConditionExpression="booking_id = :bid",
        ExpressionAttributeValues={":bid": booking_id},
        Limit=1,
    )

    items = response.get("Items", [])
    if not items:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "not found"}),
        }

    item = items[0]
    ordered = OrderedDict([
        ("client_id", item.get("client_id", "")),
        ("username", item.get("username", "")),
        ("email", item.get("email", "")),
        ("concert_name", item.get("concert_name", "")),
        ("created_at", _format_created_at(item.get("created_at"))),
    ])

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(ordered),
    }
