import json
import os
import boto3
from boto3.dynamodb.conditions import Key, Attr
from decimal import Decimal

TABLE_NAME = os.environ.get("TABLE_NAME", "books")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            if o % 1 == 0:
                return int(o)
            return float(o)
        return super().default(o)


def _response(status, body):
    return {
        "statusCode": status,
        "statusDescription": f"{status} OK",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=DecimalEncoder, ensure_ascii=False),
    }


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    client_id = params.get("client_id")

    try:
        if client_id:
            result = table.query(
                IndexName="client_id-index",
                KeyConditionExpression=Key("client_id").eq(client_id),
            )
            items = result.get("Items", [])
        else:
            result = table.scan()
            items = result.get("Items", [])

        out = []
        for it in items:
            out.append(
                {
                    "username": it.get("username"),
                    "email": it.get("email"),
                    "concert_name": it.get("concert_name"),
                }
            )
        return _response(200, out)
    except Exception as e:
        return _response(500, {"error": str(e)})
