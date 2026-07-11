#!/bin/bash
set -euo pipefail

REGION="${1:-ap-southeast-1}"
APP="${2:-gj2026-data-flink}"
NLB="${3:?NLB DNS required}"

source /root/projects/korean_skills_2026/build/load-env.sh
load_repo_env /root/projects/korean_skills_2026/build

wait_app() {
  local want="$1"
  for _ in $(seq 1 90); do
    local status
    status=$(aws kinesisanalyticsv2 describe-application \
      --application-name "$APP" --region "$REGION" \
      --query 'ApplicationDetail.ApplicationStatus' --output text 2>/dev/null || echo "UNKNOWN")
    [ "$status" = "$want" ] && return 0
    sleep 10
  done
  echo "Timed out waiting for $want (last=$status)" >&2
  return 1
}

status=$(aws kinesisanalyticsv2 describe-application \
  --application-name "$APP" --region "$REGION" \
  --query 'ApplicationDetail.ApplicationStatus' --output text)

if [ "$status" = "RUNNING" ]; then
  aws kinesisanalyticsv2 stop-application --application-name "$APP" --region "$REGION" >/dev/null || true
  wait_app READY || true
fi

aws kinesisanalyticsv2 start-application --application-name "$APP" --region "$REGION" >/dev/null || true
wait_app RUNNING

FULL=$(aws kinesisanalyticsv2 create-application-presigned-url \
  --application-name "$APP" --url-type ZEPPELIN_UI_URL --region "$REGION" --output text)
[ -n "$FULL" ]
BASE="${FULL%%\?*}"
COOKIE=/tmp/gj2026-flink-zeppelin-cookie.txt
curl -skL -c "$COOKIE" -b "$COOKIE" "$FULL" -o /dev/null

api() {
  curl -skL -b "$COOKIE" -H 'Content-Type: application/json' "$@"
}

NOTE=$(api -X POST -d "{\"name\":\"gj2026-analytics-$(date +%s)\"}" "${BASE}/api/notebook" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('body') or d.get('message') or '')")
[ -n "$NOTE" ]

add_paragraph() {
  local title="$1"
  local text="$2"
  local resp
  resp=$(api -X POST -d "$(python3 -c 'import json,sys; print(json.dumps({"title":sys.argv[1],"text":sys.argv[2]}))' "$title" "$text")" \
    "${BASE}/api/notebook/${NOTE}/paragraph")
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('body', d.get('message','')))" <<< "$resp"
}

DDL=$(cat <<SQL
%flink.ssql
CREATE TABLE IF NOT EXISTS order_logs (
  order_id STRING,
  user_id STRING,
  cart_age_seconds INT,
  status_code INT,
  latency_ms INT,
  event_time BIGINT,
  ts AS TO_TIMESTAMP(FROM_UNIXTIME(event_time / 1000)),
  WATERMARK FOR ts AS ts - INTERVAL '5' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'order-logs',
  'properties.bootstrap.servers' = '${NLB}:9094',
  'properties.group.id' = 'gj2026-flink',
  'format' = 'json',
  'scan.startup.mode' = 'earliest-offset'
);

CREATE TABLE IF NOT EXISTS sink_error_stats (
  window_start TIMESTAMP(3),
  window_end TIMESTAMP(3),
  total_count BIGINT,
  error_count BIGINT,
  error_rate DOUBLE,
  avg_latency_ms DOUBLE
) WITH (
  'connector' = 'kafka',
  'topic' = 'error-stats',
  'properties.bootstrap.servers' = '${NLB}:9094',
  'format' = 'json'
);

CREATE TABLE IF NOT EXISTS sink_high_latency (
  order_id STRING,
  user_id STRING,
  latency_ms INT,
  avg_latency_ms DOUBLE,
  proc_time STRING,
  is_anomaly INT
) WITH (
  'connector' = 'kafka',
  'topic' = 'high-latency',
  'properties.bootstrap.servers' = '${NLB}:9094',
  'format' = 'json'
);

CREATE TABLE IF NOT EXISTS sink_anomaly (
  user_id STRING,
  order_count BIGINT,
  rate_limit_count BIGINT,
  bot_suspected_count BIGINT,
  anomaly_type STRING,
  window_start TIMESTAMP(3),
  window_end TIMESTAMP(3)
) WITH (
  'connector' = 'kafka',
  'topic' = 'anomaly',
  'properties.bootstrap.servers' = '${NLB}:9094',
  'format' = 'json'
);
SQL
)

DML=$(cat <<SQL
%flink.ssql
INSERT INTO sink_error_stats
SELECT
  HOP_START(ts, INTERVAL '30' SECOND, INTERVAL '2' MINUTE) AS window_start,
  HOP_END(ts, INTERVAL '30' SECOND, INTERVAL '2' MINUTE) AS window_end,
  COUNT(*) AS total_count,
  SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) AS error_count,
  ROUND(CAST(SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*), 2) AS error_rate,
  ROUND(AVG(CAST(latency_ms AS DOUBLE)), 2) AS avg_latency_ms
FROM order_logs
GROUP BY HOP(ts, INTERVAL '30' SECOND, INTERVAL '2' MINUTE);

INSERT INTO sink_high_latency
SELECT
  order_id,
  user_id,
  latency_ms,
  avg_latency_ms,
  CAST(CURRENT_TIMESTAMP AS STRING) AS proc_time,
  CASE WHEN latency_ms > 500 THEN 1 ELSE 0 END AS is_anomaly
FROM (
  SELECT *,
    AVG(CAST(latency_ms AS DOUBLE)) OVER (
      PARTITION BY user_id ORDER BY ts
      ROWS BETWEEN 99 PRECEDING AND CURRENT ROW
    ) AS avg_latency_ms
  FROM order_logs
)
WHERE latency_ms > avg_latency_ms;

INSERT INTO sink_anomaly
SELECT user_id, order_count, rate_limit_count, bot_suspected_count, anomaly_type, window_start, window_end
FROM (
  SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(CASE WHEN status_code = 429 THEN 1 ELSE 0 END) AS rate_limit_count,
    SUM(CASE WHEN cart_age_seconds < 3 THEN 1 ELSE 0 END) AS bot_suspected_count,
    window_start,
    window_end,
    CASE
      WHEN CAST(SUM(CASE WHEN cart_age_seconds < 3 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) > 0.8 THEN 'BOT_SUSPECTED'
      WHEN CAST(SUM(CASE WHEN status_code = 429 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) > 0.5 THEN 'RATE_LIMITED'
      WHEN COUNT(*) > 150 THEN 'EXCESSIVE_ORDER'
      ELSE 'NORMAL'
    END AS anomaly_type
  FROM (
    SELECT *,
      HOP_START(ts, INTERVAL '30' SECOND, INTERVAL '2' MINUTE) AS window_start,
      HOP_END(ts, INTERVAL '30' SECOND, INTERVAL '2' MINUTE) AS window_end
    FROM order_logs
  )
  GROUP BY user_id, window_start, window_end
)
WHERE anomaly_type <> 'NORMAL';
SQL
)

add_paragraph ddl "$DDL" >/dev/null
add_paragraph dml "$DML" >/dev/null

api -X POST "${BASE}/api/notebook/job/${NOTE}" >/dev/null

for _ in $(seq 1 90); do
  running=$(api "${BASE}/api/notebook/${NOTE}" \
    | python3 -c "import json,sys; ps=json.load(sys.stdin)['body']['paragraphs']; print(sum(1 for p in ps if p.get('status')=='RUNNING'))")
  [ "$running" = "0" ] && break
  sleep 5
done

api "${BASE}/api/notebook/${NOTE}" \
  | python3 -c "import json,sys; ps=json.load(sys.stdin)['body']['paragraphs'];
[print(p.get('title'), p.get('status'), p.get('errorMessage')) for p in ps]"

echo "Flink notebook ${NOTE} deployed"
