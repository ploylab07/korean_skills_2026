#!/usr/bin/env python3
"""File-based day2/007 grading simulation against 2과제_채점지.pdf (30점 = 100%).

No live AWS / kubectl required. Runtime checks are inferred from IaC that must
produce the scored outcomes.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent


def load(rel: str) -> str:
    return (BASE / rel).read_text(errors="replace")


def has(text: str, *needles: str) -> bool:
    return all(n in text for n in needles)


def main() -> int:
    m1 = load("module1_nosql.tf")
    app = load("Module1-NoSQL/app.py")
    lam = load("Module1-NoSQL/lambda.py")
    m2 = load("module2_cdn.tf")
    req = load("Module2-CDN-Function/viewer-request.js")
    res = load("Module2-CDN-Function/viewer-response.js")
    idx_a = load("Module2-CDN-Function/index_a.html")
    idx_b = load("Module2-CDN-Function/index_b.html")
    m3e = load("module3_eks.tf")
    m3k = load("module3_k8s.tf")
    m3app = load("files/m3-app.yaml.tftpl")
    m3so = load("files/m3-scaledobject.yaml.tftpl")
    m3np = load("files/m3-nodepool.yaml.tftpl")
    m3py = load("Module3-EKS-Scaling/app.py")
    m4e = load("module4_eks.tf")
    m4k = load("module4_k8s.tf")
    m4app = load("files/m4-app.yaml.tftpl")
    m4gf = load("files/m4-grafana.yaml.tftpl")
    m4otel = load("k8s/m4-otel.yaml")
    m4py = load("Module4-Container-Logging/app.py")
    locals_tf = load("locals.tf")
    vars_tf = load("variables.tf")

    rows: list[tuple[str, float, str, str]] = []

    def add(id_: str, pts: float, ok: bool, reason: str) -> None:
        rows.append((id_, pts, "PASS" if ok else "FAIL", reason))

    # ----- Module 1 NoSQL (7.5) -----
    add(
        "1-1",
        1.5,
        has(
            m1,
            'name         = "bigbae-nosql-reservation-table"',
            'hash_key     = "train_id"',
            'range_key    = "seat_id"',
            'stream_view_type = "NEW_AND_OLD_IMAGES"',
            'billing_mode = "PAY_PER_REQUEST"',
            "point_in_time_recovery",
            "enabled = true",
        )
        and has(m1, 'name = "train_id"', 'type = "S"')
        and has(m1, 'name = "seat_id"', 'type = "S"'),
        "Reservation table + stream + PITR + PAY_PER_REQUEST",
    )
    add(
        "1-2",
        1.0,
        has(
            m1,
            'name            = "gsi-user-reservations"',
            'hash_key        = "user_id"',
            'range_key       = "reserved_at"',
            'projection_type = "ALL"',
            'name         = "bigbae-nosql-audit-table"',
            'hash_key     = "event_id"',
        ),
        "GSI + audit table",
    )
    add(
        "1-3",
        1.0,
        has(
            m1,
            'function_name    = "bigbae-nosql-reservation-audit"',
            'runtime          = "python3.13"',
            "timeout          = 30",
            "aws_lambda_event_source_mapping",
            "reservation.stream_arn",
        )
        and "handler" in lam
        and "AUDIT_TABLE_NAME" in lam,
        "Lambda + Streams trigger (lambda.py unmodified)",
    )
    add(
        "1-4",
        1.0,
        has(m1, 'Name = "bigbae-nosql-app-ec2"', "8080", "associate_public_ip_address = true")
        and has(app, "/healthcheck", 'port=8080'),
        "EC2 app server + healthcheck",
    )
    # Exact JSON key order + compact separators for scoring curl output
    reserve_ok = (
        "separators=(\",\", \":\")" in app
        and '"seat_id": seat_id' in app
        and '"status": "reserved"' in app
        and '"version": int(item["version"])' in app
        and app.index('"seat_id": seat_id') < app.index('"status": "reserved"')
        and "already reserved" in app
        and "not owner" in app
        and "ConditionalCheckFailedException" in app
        and 'ConditionExpression="attribute_not_exists(#status) OR #status = :available"' in app
        and "REMOVE user_id, reserved_at" in app
    )
    cancel_ok = '"seat_id": seat_id, "status": "cancelled"' in app or re.search(
        r'\{\s*"seat_id":\s*seat_id,\s*"status":\s*"cancelled"\s*\}', app
    )
    add("1-5", 1.5, bool(reserve_ok and cancel_ok), "Conditional write API (exact JSON order)")
    add(
        "1-6",
        1.5,
        has(app, "/my-bookings/", "/seats/", "IndexName=GSI_NAME", "KeyConditionExpression")
        and has(m1, "aws_lambda_event_source_mapping", "AUDIT_TABLE_NAME")
        and has(lam, "train_id", "seat_id", "user_id", "occurred_at"),
        "Streams audit + read APIs",
    )

    # ----- Module 2 CDN (7.5) -----
    add(
        "2-1",
        1.0,
        "skillsphone-landing-ab-" in locals_tf
        and has(
            m2,
            "local.landing_bucket_name",
            "version-a/index.html",
            "version-b/index.html",
            "block_public_acls       = true",
            "block_public_policy     = true",
            "ignore_public_acls      = true",
            "restrict_public_buckets = true",
            "cloudfront.amazonaws.com",
            "AWS:SourceArn",
            "aws_cloudfront_origin_access_control",
        )
        and "version_a" in idx_a
        and "version_b" in idx_b,
        "S3 bucket + objects + PAB + OAC policy",
    )
    add(
        "2-2",
        1.0,
        has(
            m2,
            'name     = "skillsphone-cdn-ab-config"',
            'key                  = "weight"',
            'value                = "0.3"',
            'key                  = "version_a"',
            'value                = "/version-a/index.html"',
            'key                  = "version_b"',
            'value                = "/version-b/index.html"',
            'name     = "skillsphone-cdn-ab-req-fn"',
            'name     = "skillsphone-cdn-ab-res-fn"',
            'runtime  = "cloudfront-js-2.0"',
            "publish  = true",
            "key_value_store_associations",
        ),
        "KVS keys + CF functions LIVE + KVS assoc",
    )
    add(
        "2-3",
        1.0,
        has(
            m2,
            'name        = "skillsphone-cdn-ab-cache-policy"',
            "min_ttl     = 0",
            "default_ttl = 300",
            "max_ttl     = 3600",
            'cookie_behavior = "whitelist"',
            '"x-sp-ab"',
            'comment             = "skillsphone-cdn-ab-distribution"',
            'viewer_protocol_policy  = "redirect-to-https"',
            "origin_access_control_id",
            'event_type   = "viewer-request"',
            'event_type   = "viewer-response"',
            "response_headers_policy_id",
        ),
        "Cache policy + distribution associations",
    )
    # Cookie force + no Set-Cookie when cookie present + HTTP→HTTPS
    cookie_force = (
        "cookies['x-sp-ab']" in req
        and "request.uri = uri" in req
        and "x-sp-ab-assigned" in req
        and "x-sp-ab-assigned" in res
        and "Max-Age=86400" in res
        and "Path=/" in res
        and 'viewer_protocol_policy  = "redirect-to-https"' in m2
    )
    add("2-4", 1.5, cookie_force, "A/B cookie force + HTTPS redirect (inferred)")
    sticky = (
        "isNew" in req
        and "Math.random()" in req
        and "weight" in req
        and "x-sp-ab-assigned" in res
        and "Max-Age=86400" in res
        and "Path=/" in res
    )
    add("2-5", 1.5, sticky, "Random assign + sticky cookie (inferred)")
    weight_dyn = (
        "kvsHandle.get('weight')" in req
        and "rand < weight" in req
        and "assigned = 'b'" in req
        and "assigned = 'a'" in req
        and has(m2, 'value                = "0.3"')
    )
    add("2-6", 1.5, weight_dyn, "KVS weight dynamic routing (inferred)")

    # ----- Module 3 EKS Scaling (7.5) -----
    add("3-1", 0.35, 'name     = "skm-order-queue"' in m3e, "SQS skm-order-queue")
    add(
        "3-2",
        0.75,
        has(
            m3e,
            'name     = "skm-eks-cluster"',
            'version  = var.eks_version',
            'node_group_name = "skm-cluster-addon-ng"',
            'instance_types  = ["t3.medium"]',
            "min_size     = 1",
            "desired_size = 1",
            "max_size     = 1",
            'Name = "skm-cluster-addon-ng-node"',
            'key    = "CriticalAddonsOnly"',
        )
        and 'default = "1.35"' in vars_tf,
        "EKS 1.35 + addon NG taint/tag",
    )
    add(
        "3-3",
        1.0,
        has(
            m3app,
            "name: order-processor",
            "namespace: skillsmkt",
            "replicas: 1",
            "containerPort: 8080",
            "cpu: 500m",
            "memory: 512Mi",
            "AWS_REGION",
            "ap-northeast-2",
            "SQS_QUEUE_URL",
            'PROCESSING_TIME\n          value: "3"',
            "karpenter.sh/nodepool: skm-app-nodepool",
            "key: skm-app",
        )
        and has(m3py, "/healthz", "/status", "receive_message", "delete_message"),
        "order-processor deploy + env PROCESSING_TIME=3",
    )
    add(
        "3-4",
        1.2,
        has(
            m3k,
            "kedacore/keda",
            "--namespace keda",
        )
        and has(
            m3so,
            "name: order-scaler",
            "namespace: skillsmkt",
            "minReplicaCount: 1",
            "maxReplicaCount: 5",
            "type: aws-sqs-queue",
            'queueLength: "5"',
        ),
        "KEDA + ScaledObject 1/5 queueLength=5",
    )
    add(
        "3-5",
        1.2,
        has(
            m3k,
            "karpenter/karpenter",
            "--namespace kube-system",
        )
        and has(
            m3np,
            "name: skm-app-nodepool",
            "name: skm-app-nodeclass",
            "consolidationPolicy: WhenEmptyOrUnderutilized",
            "consolidateAfter: 60s",
            '"t3.small"',
            '"t3.medium"',
            "key: skm-app",
            "effect: NoSchedule",
        ),
        "Karpenter NodePool/EC2NodeClass + 60s consolidation",
    )
    # Scale-out: 100 msgs, queueLength 5 → max 5 pods; 5*500m needs ≥2 nodes
    scale_out_ready = (
        'maxReplicaCount: 5' in m3so
        and 'queueLength: "5"' in m3so
        and "cpu: 500m" in m3app
        and "memory: 512Mi" in m3app
        and '"t3.small"' in m3np
        and '"t3.medium"' in m3np
        and 'PROCESSING_TIME\n          value: "3"' in m3app
    )
    add("3-6", 1.5, scale_out_ready, "Scale-out config (pods≥5, nodes≥2 inferred)")
    scale_in_ready = (
        "minReplicaCount: 1" in m3so
        and "consolidateAfter: 60s" in m3np
        and "WhenEmptyOrUnderutilized" in m3np
        and "cooldownPeriod: 30" in m3so
    )
    add("3-7", 1.5, scale_in_ready, "Scale-in config (pods=1, nodes=1 inferred)")

    # ----- Module 4 Container Logging (7.5) -----
    add(
        "4-1",
        1.0,
        has(
            m4e,
            'name     = "o11y-cluster"',
            'version  = var.eks_version',
            'instance_types  = ["t3.medium"]',
            "min_size     = 2",
            "desired_size = 2",
            "max_size     = 2",
            "timedatectl set-timezone Asia/Seoul",
            "aws_subnet.m4_private_a",
            "aws_subnet.m4_private_b",
        )
        and 'default = "1.35"' in vars_tf,
        "o11y EKS multi-AZ + Asia/Seoul",
    )
    add(
        "4-2",
        1.0,
        has(
            m4e,
            'name               = "o11y-app-alb"',
            'name               = "o11y-grafana-alb"',
            'name        = "o11y-app-tg"',
            'name        = "o11y-grafana-tg"',
            "load_balancer_type = \"application\"",
            "internal           = false",
            'target_type = "ip"',
        )
        and has(m4app, "TargetGroupBinding", "o11y-app-tgb")
        and has(m4gf, "TargetGroupBinding", "o11y-grafana-tgb"),
        "App/Grafana ALB + TG + bindings",
    )
    add(
        "4-3",
        1.0,
        has(m4app, "name: log-generator", "namespace: o11y", "replicas: 2")
        and has(m4otel, "name: o11y-otel", "kind: DaemonSet", "namespace: monitoring")
        and has(m4k, "helm upgrade --install o11y-loki", "deploymentMode=SingleBinary")
        and has(m4gf, "name: o11y-grafana", "replicas: 1")
        and "o11y-loki" in m4k,
        "Workloads: log-generator/otel/loki/grafana",
    )
    add(
        "4-4",
        1.5,
        has(m4py, "/healthz", '"status": "ok"', "/log", "level", "generated")
        and has(m4e, 'path                = "/healthz"')
        and has(m4app, "TargetGroupBinding"),
        "App API via ALB (healthz + log)",
    )
    pipeline = (
        has(m4otel, "filelog", "/var/log/pods/*/*/*.log", "k8sattributes", "otlphttp")
        and "o11y-loki.monitoring.svc.cluster.local:3100/otlp" in m4otel
        and has(m4k, "o11y-loki", "SingleBinary")
        and '"level": level' in m4py
        and "json.dumps" in m4py
    )
    add("4-5", 1.5, pipeline, "OTel→Loki pipeline + LogQL-ready ERROR logs")
    dash = (
        has(
            m4gf,
            "Log Overview",
            "Log Count Over Time",
            "barchart",
            "Log Level Distribution",
            "piechart",
            "Recent Logs",
            '"type": "logs"',
            'legendFormat": "error"',
            'legendFormat": "warn"',
            'legendFormat": "info"',
            "url: http://o11y-loki.monitoring.svc.cluster.local:3100",
            "type: loki",
        )
        and has(locals_tf, "skills${local.player_number}", "GoodJob!Skills${local.player_number}^^")
        and has(m4e, 'name               = "o11y-grafana-alb"')
    )
    add("4-6", 1.5, dash, "Grafana datasource + Log Overview dashboard panels")

    total = sum(p for _, p, s, _ in rows if s == "PASS")
    maxt = sum(p for _, p, _, _ in rows)
    pct = round(total / maxt * 100) if maxt else 0
    print("=== day2/007 채점 시뮬레이션 (채점지 30점 = 100%) ===\n")
    for id_, pts, st, reason in rows:
        print(f"[{st}] {id_} {pts} — {reason}")
    print(f"\n합계: {total}/{maxt} = {pct}점")
    fails = [x for x in rows if x[2] == "FAIL"]
    if fails:
        print("\n감점:")
        for id_, pts, _, reason in fails:
            print(f"  - {id_} (-{pts}): {reason}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
