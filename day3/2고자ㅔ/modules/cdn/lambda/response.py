def handler(event, context):
    response = event["Records"][0]["cf"]["response"]
    headers = response.setdefault("headers", {})
    headers["cache-control"] = [{"key": "Cache-Control", "value": "public, max-age=86400"}]
    headers["content-type"] = [{"key": "Content-Type", "value": "image/png"}]
    return response
