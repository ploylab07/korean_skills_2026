def handler(event, context):
    request = event["Records"][0]["cf"]["request"]
    uri = request.get("uri", "/")
    if uri.startswith("/images"):
        request["uri"] = "/"
    return request
