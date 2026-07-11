import json
import os
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    client_id = params.get("client_id")
    if not client_id:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"msg": "client_id required"}),
        }

    resp = table.get_item(Key={"client_id": client_id})
    item = resp.get("Item")
    if not item:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"msg": "Item not found"}),
        }

    body = {
        "username": item.get("username", ""),
        "booking_id": item.get("booking_id", ""),
        "email": item.get("email", ""),
        "client_id": item.get("client_id", ""),
        "concert_name": item.get("concert_name", ""),
    }
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
