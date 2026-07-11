#!/bin/bash
set -euo pipefail

GRAFANA_PASS='Skills$#$@!'
REGION="ap-northeast-2"

for i in $(seq 1 60); do
  GRAFANA_LB=$(kubectl get svc -n observability kube-prometheus-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$GRAFANA_LB" ] && break
  sleep 10
done
[ -z "$GRAFANA_LB" ] && echo "Grafana LB not ready" && exit 1

auth() {
  curl -s -u "admin:${GRAFANA_PASS}" "$@"
}

add_ds() {
  local name=$1 type=$2 url=$3 extra=${4:-{}}
  auth -X POST "http://${GRAFANA_LB}/api/datasources" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${name}\",\"type\":\"${type}\",\"access\":\"proxy\",\"url\":\"${url}\",\"isDefault\":false,\"jsonData\":${extra}}" \
    >/dev/null 2>&1 || true
}

add_ds "prometheus" "prometheus" "http://kube-prometheus-kube-prome-prometheus.observability.svc:9090"
add_ds "alertmanager" "alertmanager" "http://kube-prometheus-kube-prome-alertmanager.observability.svc:9093" '{"implementation":"prometheus"}'
add_ds "cloudwatch" "cloudwatch" "" "{\"defaultRegion\":\"${REGION}\"}"

DASHBOARD='{
  "dashboard": {
    "title": "wsc2026-grafana-dashboard",
    "uid": "wsc2026-dashboard",
    "tags": ["wsc2026"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "10s",
    "panels": [
      {"type":"row","title":"Node","gridPos":{"h":1,"w":24,"x":0,"y":0}},
      {"type":"timeseries","title":"Node CPU","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":12,"x":0,"y":1},"targets":[{"expr":"100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)","legendFormat":"{{instance}}"}],"fieldConfig":{"defaults":{"unit":"percent","thresholds":{"mode":"absolute","steps":[{"color":"green","value":null},{"color":"yellow","value":60},{"color":"red","value":80}]}}}},
      {"type":"timeseries","title":"Node Memory","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":12,"x":12,"y":1},"targets":[{"expr":"(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100","legendFormat":"{{instance}}"}],"fieldConfig":{"defaults":{"unit":"percent","thresholds":{"mode":"absolute","steps":[{"color":"green","value":null},{"color":"yellow","value":60},{"color":"red","value":80}]}}}},
      {"type":"stat","title":"Available Nodes","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":4,"w":24,"x":0,"y":9},"targets":[{"expr":"count(kube_node_status_condition{condition=\"Ready\",status=\"true\"})"}]},
      {"type":"row","title":"Pod","gridPos":{"h":1,"w":24,"x":0,"y":13}},
      {"type":"timeseries","title":"Pod CPU","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":12,"x":0,"y":14},"targets":[{"expr":"sum by(pod) (rate(container_cpu_usage_seconds_total{namespace=\"wsc2026\",container!=\"\"}[5m]))","legendFormat":"{{pod}}"}]},
      {"type":"timeseries","title":"Pod Memory","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":12,"x":12,"y":14},"targets":[{"expr":"sum by(pod) (container_memory_working_set_bytes{namespace=\"wsc2026\",container!=\"\"})","legendFormat":"{{pod}}"}]},
      {"type":"stat","title":"Pending Pods","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":4,"w":12,"x":0,"y":22},"targets":[{"expr":"count(kube_pod_status_phase{namespace=\"wsc2026\",phase=\"Pending\"}) or vector(0)"}]},
      {"type":"stat","title":"Pod Restarts","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":4,"w":12,"x":12,"y":22},"targets":[{"expr":"sum(kube_pod_container_status_restarts_total{namespace=\"wsc2026\"})"}],"fieldConfig":{"defaults":{"thresholds":{"mode":"absolute","steps":[{"color":"green","value":null},{"color":"red","value":1}]}}}},
      {"type":"row","title":"Application Pod","gridPos":{"h":1,"w":24,"x":0,"y":26}},
      {"type":"timeseries","title":"App Pod CPU","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":12,"x":0,"y":27},"targets":[{"expr":"sum by(pod) (rate(container_cpu_usage_seconds_total{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\"}[5m]))","legendFormat":"{{pod}}"}]},
      {"type":"timeseries","title":"App Pod Memory","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":12,"x":12,"y":27},"targets":[{"expr":"sum by(pod) (container_memory_working_set_bytes{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\"})","legendFormat":"{{pod}}"}]},
      {"type":"stat","title":"Running App Pods","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":4,"w":8,"x":0,"y":35},"targets":[{"expr":"count(kube_pod_status_phase{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\",phase=\"Running\"})"}]},
      {"type":"stat","title":"App Restarts","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":4,"w":8,"x":8,"y":35},"targets":[{"expr":"sum(kube_pod_container_status_restarts_total{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\"})"}]},
      {"type":"stat","title":"App Pending","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":4,"w":8,"x":16,"y":35},"targets":[{"expr":"count(kube_pod_status_phase{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\",phase=\"Pending\"}) or vector(0)"}]},
      {"type":"row","title":"Application Traffic","gridPos":{"h":1,"w":24,"x":0,"y":39}},
      {"type":"timeseries","title":"Request Count","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":8,"x":0,"y":40},"targets":[{"expr":"sum(rate(nginx_ingress_controller_requests{namespace=\"wsc2026\"}[5m])) or sum(rate(prometheus_http_requests_total[5m]))","legendFormat":"requests"}]},
      {"type":"timeseries","title":"Response Time","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":8,"x":8,"y":40},"targets":[{"expr":"histogram_quantile(0.95, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (le)) or vector(0)","legendFormat":"p95"}]},
      {"type":"timeseries","title":"Status Codes","datasource":{"type":"prometheus","uid":"prometheus"},"gridPos":{"h":8,"w":8,"x":16,"y":40},"targets":[{"expr":"sum by(code) (rate(nginx_ingress_controller_requests{namespace=\"wsc2026\"}[5m])) or sum by(code) (rate(prometheus_http_requests_total[5m]))","legendFormat":"{{code}}"}]},
      {"type":"logs","title":"Application Logs","datasource":{"type":"cloudwatch","uid":"cloudwatch"},"gridPos":{"h":10,"w":24,"x":0,"y":48},"targets":[{"datasource":{"type":"cloudwatch","uid":"cloudwatch"},"queryMode":"Logs","logGroupNames":["/wsc2026/application"],"region":"ap-northeast-2"}]},
      {"type":"row","title":"Alerts","gridPos":{"h":1,"w":24,"x":0,"y":58}},
      {"type":"alertlist","title":"Alert Rules","gridPos":{"h":8,"w":24,"x":0,"y":59},"options":{"showOptions":"current","maxItems":20,"sortOrder":1}}
    ]
  },
  "overwrite": true,
  "folderUid": "wsc2026",
  "message": "wsc2026 dashboard import"
}'

auth -X POST "http://${GRAFANA_LB}/api/folders" \
  -H 'Content-Type: application/json' \
  -d '{"uid":"wsc2026","title":"wsc2026"}' >/dev/null 2>&1 || true

auth -X POST "http://${GRAFANA_LB}/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d "$DASHBOARD" >/dev/null

create_alert() {
  local title=$1 expr=$2 threshold=$3
  auth -X POST "http://${GRAFANA_LB}/api/v1/provisioning/alert-rules" \
    -H 'Content-Type: application/json' \
    -d "{
      \"title\": \"${title}\",
      \"ruleGroup\": \"wsc2026\",
      \"folderUID\": \"wsc2026\",
      \"condition\": \"C\",
      \"noDataState\": \"OK\",
      \"execErrState\": \"Alerting\",
      \"for\": \"1m\",
      \"uid\": \"$(echo -n "$title" | md5sum | cut -c1-8)\",
      \"data\": [{
        \"refId\": \"A\",
        \"relativeTimeRange\": {\"from\": 300, \"to\": 0},
        \"datasourceUid\": \"prometheus\",
        \"model\": {\"expr\": \"${expr}\", \"intervalMs\": 1000, \"maxDataPoints\": 43200, \"refId\": \"A\"}
      }, {
        \"refId\": \"C\",
        \"relativeTimeRange\": {\"from\": 0, \"to\": 0},
        \"datasourceUid\": \"__expr__\",
        \"model\": {\"conditions\": [{\"evaluator\": {\"params\": [${threshold}], \"type\": \"gt\"}, \"operator\": {\"type\": \"and\"}, \"query\": {\"params\": [\"C\"]}, \"reducer\": {\"params\": [], \"type\": \"last\"}, \"type\": \"query\"}], \"datasource\": {\"type\": \"__expr__\", \"uid\": \"__expr__\"}, \"expression\": \"A\", \"refId\": \"C\", \"type\": \"threshold\"}
      }]
    }" >/dev/null 2>&1 || true
}

create_alert "PodHighCPU" "max(rate(container_cpu_usage_seconds_total{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\"}[5m])) * 100" "80"
create_alert "PodHighMemory" "max(container_memory_working_set_bytes{namespace=\"wsc2026\",pod=~\"wsc2026-book-deploy.*\"}) / 1024 / 1024" "400"
create_alert "PodNotReady" "count(kube_pod_status_ready{namespace=\"wsc2026\",condition=\"false\",pod=~\"wsc2026-book-deploy.*\"}) or vector(0)" "0"
create_alert "HighErrorRate" "sum(rate(prometheus_http_requests_total{code=~\"5..\"}[5m])) or vector(0)" "0"
create_alert "HighLatency" "histogram_quantile(0.95, sum(rate(prometheus_http_request_duration_seconds_bucket[5m])) by (le)) or vector(0)" "1"

echo "Grafana setup complete: http://${GRAFANA_LB}"
