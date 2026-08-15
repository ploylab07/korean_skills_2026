import json
import os
import time
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

TABLE_NAME = os.environ.get("TABLE_NAME", "books")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
METRIC_NS = "gj2026/BookReservation"


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


def _emit_metric(client_id_dim):
    """Embedded Metric Format → CloudWatch (per client_id + ALL aggregate)."""
    ts = int(time.time() * 1000)
    dims = ["ALL"] if client_id_dim == "ALL" else [client_id_dim, "ALL"]
    for dim in dims:
        print(
            json.dumps(
                {
                    "_aws": {
                        "Timestamp": ts,
                        "CloudWatchMetrics": [
                            {
                                "Namespace": METRIC_NS,
                                "Dimensions": [["client_id"]],
                                "Metrics": [{"Name": "InvocationCount", "Unit": "Count"}],
                            }
                        ],
                    },
                    "client_id": dim,
                    "InvocationCount": 1,
                }
            )
        )


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
            _emit_metric(client_id)
        else:
            result = table.scan()
            items = result.get("Items", [])
            _emit_metric("ALL")

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
