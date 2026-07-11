import base64
import io
import os
from urllib.parse import unquote

import boto3
from PIL import Image

S3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]
PREFIX = os.environ.get("IMAGE_PREFIX", "images/")


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    image = unquote(params.get("image", "dog"))
    rotate = int(params.get("rotate", "0") or 0) % 360

    key = f"{PREFIX}{image}.png"
    obj = S3.get_object(Bucket=BUCKET, Key=key)
    raw = obj["Body"].read()

    if rotate == 0:
        body = base64.b64encode(raw).decode("ascii")
    else:
        img = Image.open(io.BytesIO(raw))
        if rotate:
            img = img.rotate(-rotate, expand=True)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        body = base64.b64encode(buf.getvalue()).decode("ascii")

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "image/png",
            "Cache-Control": "public, max-age=86400",
        },
        "body": body,
        "isBase64Encoded": True,
    }
