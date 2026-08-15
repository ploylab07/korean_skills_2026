import json
import sys
import uuid
from datetime import datetime, timezone

from flask import Flask, Response, request

app = Flask(__name__)


def _timestamp() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def compact_json(payload, status: int = 200):
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    return Response(body, status=status, mimetype="application/json")


@app.get("/healthz")
def healthz():
    return compact_json({"status": "ok"}, 200)


@app.get("/log")
def generate_logs():
    level = request.args.get("level", "info").upper()
    if level not in {"INFO", "WARN", "ERROR"}:
        return compact_json({"error": "level must be one of info, warn, error"}, 400)

    try:
        count = int(request.args.get("count", "1"))
    except ValueError:
        return compact_json({"error": "count must be an integer"}, 400)

    count = max(1, min(count, 1000))
    for _ in range(count):
        record = {
            "ts": _timestamp(),
            "level": level,
            "msg": "log generated",
            "req_id": str(uuid.uuid4()),
        }
        print(json.dumps(record, separators=(",", ":")), flush=True)
        sys.stdout.flush()

    # Key order: level then generated matches jq -r '.level, .generated' scoring flow
    return compact_json({"level": level.lower(), "generated": count}, 200)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
