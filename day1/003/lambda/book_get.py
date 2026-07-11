import json
import os
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def format_created_at(value: str) -> str:
    if not value:
        return ""
    try:
        if value.endswith("Z"):
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        elif "T" in value:
            dt = datetime.fromisoformat(value)
        else:
            return value
        return dt.astimezone(ZoneInfo("Asia/Seoul")).strftime("%Y-%m-%d %H:%M:%S KST")
    except Exception:
        return value


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    booking_id = params.get("booking_id", "")
    if not booking_id:
        return {"statusCode": 400, "body": json.dumps({"error": "booking_id required"})}

    response = table.query(
        IndexName="booking_id-index",
        KeyConditionExpression=Key("booking_id").eq(booking_id),
    )
    items = response.get("Items", [])
    if not items:
        return {"statusCode": 404, "body": json.dumps({"error": "not found"})}

    item = items[0]
    body = {
        "client_id": item.get("client_id", ""),
        "username": item.get("username", ""),
        "email": item.get("email", ""),
        "concert_name": item.get("concert_name", ""),
        "created_at": format_created_at(item.get("created_at", "")),
    }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }
