import json
import os

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ.get("TABLE_NAME", "unicorn-concert-db")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

FIELDS = ["booking_id", "client_id", "username", "email", "concert_name", "created_at"]


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "statusDescription": f"{status_code} {'OK' if status_code == 200 else 'Error'}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    booking_id = params.get("booking_id")

    if not booking_id:
        return _response(400, {"error": "booking_id is required"})

    try:
        result = table.get_item(Key={"booking_id": booking_id})
        item = result.get("Item")

        if not item:
            return _response(404, {"error": "booking not found"})

        email = params.get("email")
        if email and item.get("email") != email:
            return _response(404, {"error": "booking not found"})

        concert_name = params.get("concert_name")
        if concert_name and item.get("concert_name") != concert_name:
            return _response(404, {"error": "booking not found"})

        body = {field: item[field] for field in FIELDS if field in item}
        return _response(200, body)
    except Exception as exc:  # noqa: BLE001 - surface as a clean 500 for the client
        return _response(500, {"error": str(exc)})
