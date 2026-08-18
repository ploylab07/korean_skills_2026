import json
import os
from collections import OrderedDict
from datetime import datetime, timezone, timedelta
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

# 9-2-A 채점: POST 바디와 같은 키 순서
ITEM_FIELDS = ("client_id", "username", "email", "concert_name", "created_at")

TABLE_NAME = os.environ["TABLE_NAME"]
INDEX_NAME = os.environ.get("INDEX_NAME", "concert_name-created_at-index")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
KST = timezone(timedelta(hours=9))


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return int(o) if o % 1 == 0 else float(o)
        return super().default(o)


def _response(status, body):
    return {
        "statusCode": status,
        "statusDescription": f"{status} {'OK' if status == 200 else 'Bad Request' if status == 400 else 'Error'}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False, cls=DecimalEncoder),
    }


def to_kst(value: str) -> str:
    if not value:
        return value
    try:
        s = value.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(KST).isoformat()
    except Exception:
        return value


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    concert_name = params.get("concert_name")
    if not concert_name:
        return _response(400, {"message": "concert_name is required"})

    result = table.query(
        IndexName=INDEX_NAME,
        KeyConditionExpression=Key("concert_name").eq(concert_name),
        ScanIndexForward=False,
    )
    items = []
    for item in result.get("Items", []):
        ordered = OrderedDict()
        for field in ITEM_FIELDS:
            if field not in item:
                continue
            value = item[field]
            if field == "created_at":
                value = to_kst(value)
            ordered[field] = value
        items.append(ordered)
    return _response(200, items)
