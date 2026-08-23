#!/usr/bin/env python3
"""day2/002 채점 시뮬레이션 (mark2-1~4.sh + 지급 명세 기준, AWS 호출 없음).

Usage:
  python3 simulate_grade.py
"""
from __future__ import annotations

import csv
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent
rows: list[tuple[str, float, str, str]] = []


def load(*parts: str) -> str:
    return (BASE.joinpath(*parts)).read_text(errors="replace")


def exists(*parts: str) -> bool:
    return BASE.joinpath(*parts).is_file()


def add(id_: str, pts: float, ok: bool, reason: str) -> None:
    rows.append((id_, pts, "PASS" if ok else "FAIL", reason))


def has(text: str, *needles: str) -> bool:
    return all(n in text for n in needles)


def main() -> int:
    wf = load("modules/workflow/main.tf")
    an = load("modules/analytics/main.tf")
    ud = load("modules/analytics/userdata.sh.tpl")
    ev = load("modules/event/main.tf")
    mk = load("modules/msk/main.tf")
    mk_ud = load("modules/msk/user_data.sh.tftpl")
    score_py = load("module1/lambda-function.py")
    event_py = load("module3/lambda-function.py")
    sensor_py = load("modules/msk/lambda/sensor-consumer/index.py")
    alert_py = load("modules/msk/lambda/alert-consumer/index.py")
    app_py = load("module2/app.py")
    main_tf = load("main.tf")
    csv_text = load("module1/test.csv")

    # ----- Module 1 (8.0) -----
    add(
        "1-1",
        1.5,
        has(wf, "wsc2026-student-score-bucket-", 'key          = each.value', "input/", "processed/", "error/"),
        "S3 bucket + input/processed/error folders",
    )
    add(
        "1-2",
        1.5,
        has(wf, 'name         = "wsc2026-student-score"', 'hash_key     = "studentId"', 'range_key    = "examDate"'),
        "DynamoDB table + key schema",
    )
    add(
        "1-3",
        1.5,
        has(
            wf,
            'function_name    = "wsc2026-student-score-function"',
            'runtime          = "python3.12"',
            "S3_BUCKET",
            "DDB_TABLE",
        )
        and has(score_py, "calculate_grade", "save_student", "validate_row", 'statusCode": 200'),
        "Lambda runtime + env + processing code",
    )
    add(
        "1-4",
        1.5,
        has(
            wf,
            'name         = "wsc2026-student-score-workflow"',
            'type         = "STANDARD"',
            "CheckS3File",
            "ProcessStudentData",
            "BackoffRate",
            "wsc2026-student-score-trigger",
            "filter_prefix       = \"input/\"",
            "filter_suffix       = \".csv\"",
        ),
        "Step Functions STANDARD + S3 trigger + Retry backoff",
    )

    reader = list(csv.DictReader(csv_text.splitlines()))
    stu = next((r for r in reader if r.get("studentId") == "STU1020"), None)
    scores_ok = False
    if stu:
        try:
            vals = [int(stu[f]) for f in ("korean", "english", "math", "science", "history")]
            avg = round(sum(vals) / 5, 1)
            scores_ok = avg >= 90  # expect grade A in DDB for mark 1-5-A
        except Exception:
            scores_ok = False
    err_rows = sum(1 for r in reader if not all((r.get(f) or "").strip() for f in ("studentId", "name", "korean", "english", "math", "science", "history")) or not (r.get("english") or "").lstrip("+-").isdigit())
    add(
        "1-5-A",
        1.0,
        bool(stu)
        and scores_ok
        and has(wf, "MoveToProcessed", "processed/", "input/test.csv")
        and "STU1020" in csv_text,
        "Normal path: STU1020 → DDB + processed/",
    )
    add(
        "1-5-B",
        1.0,
        err_rows >= 1 and has(wf, "MoveToError", "error/") and "save_error" in score_py,
        "Error path: invalid rows → error/ JSON",
    )

    # ----- Module 2 (8.0) -----
    add(
        "2-1",
        1.0,
        has(an, 'Name = "wsc2026-analytics-ec2"', 'Name = "analytics-priv-a"', "aws_subnet.private_a.id"),
        "EC2 in analytics-priv-a",
    )
    add(
        "2-2",
        1.0,
        has(
            an,
            'name               = "wsc2026-analytics-alb"',
            'name        = "wsc2026-analytics-tg"',
            "port        = 5000",
            'protocol    = "HTTP"',
            "aws_lb_listener",
        ),
        "ALB + TG :5000 + HTTP listener",
    )
    add(
        "2-3-A",
        1.0,
        has(an, 'name             = "wsc2026-order-stream"', 'stream_mode = "ON_DEMAND"'),
        "Kinesis ON_DEMAND stream",
    )
    add(
        "2-3-B",
        1.0,
        has(app_py, '@app.route("/order"', "kinesis.put_record", "STREAM_NAME")
        and has(ud, "STREAM_NAME=wsc2026-order-stream", "gunicorn"),
        "POST /order → Kinesis (app + userdata)",
    )
    add(
        "2-4",
        1.5,
        has(
            an,
            'name                   = "wsc2026-analytics-flink"',
            'runtime_environment    = "ZEPPELIN-FLINK-3_0"',
            "aws_kinesisanalyticsv2_application",
        ),
        "Managed Flink application",
    )
    add(
        "2-5",
        1.0,
        has(app_py, '@app.route("/health"', "healthy") and has(an, 'path     = "/health"'),
        "ALB health check /health",
    )
    add(
        "2-6",
        1.5,
        has(ud, "app.service", "systemctl enable --now app", "WantedBy=multi-user.target"),
        "systemd app service enabled",
    )

    # ----- Module 3 (7.0) -----
    add(
        "3-1",
        1.5,
        has(
            ev,
            'name     = "wsc2026-event-alert"',
            'function_name    = "wsc2026-ec2-stop-remediation"',
            'function_name    = "wsc2026-ec2-terminate-alert"',
            'function_name    = "wsc2026-sg-remediation"',
            'function_name    = "wsc2026-tag-alert"',
            'runtime          = "python3.12"',
        )
        and has(event_py, "sg_remediation_handler", "ec2_stop_remediation_handler", "ec2_terminate_handler", "tag_alert_handler"),
        "SNS + 4 Lambda functions",
    )
    add(
        "3-2",
        1.5,
        has(
            ev,
            'name     = "wsc2026-ec2-stop-rule"',
            'name     = "wsc2026-ec2-terminate-rule"',
            "aws_cloudwatch_event_target",
            "stop-remediation",
            "terminate-alert",
        ),
        "EventBridge stop/terminate rules → Lambda",
    )
    add(
        "3-3",
        1.5,
        has(
            ev,
            'name     = "wsc2026-sg-ssh-rule"',
            'name     = "wsc2026-required-tags-rule"',
            "INCOMING_SSH_DISABLED",
            "REQUIRED_TAGS",
        ),
        "Config rules SSH + required tags",
    )
    add(
        "3-4",
        1.5,
        has(event_py, "start_instances", "revoke_security_group_ingress")
        and has(ev, "wsc2026-sg-change-rule", "AuthorizeSecurityGroupIngress", "state = [\"stopped\"]"),
        "Stop restart + SG ingress remediation wiring",
    )
    add(
        "3-5",
        1.0,
        has(ev, 'resource "aws_instance" "tag_noncompliant"', "wsc2026-required-tags-rule", "NON_COMPLIANT"),
        "Non-compliant instance for tag Config check",
    )

    # ----- Module 4 (7.0) -----
    add(
        "4-1",
        1.5,
        has(mk, 'name_prefix       = "wsc2026"', "sensor-data", "sensorId", "timestamp", "sensor-alert-bucket-")
        and exists("module4", "app"),
        "DynamoDB + S3 alert bucket (+ producer binary)",
    )
    add(
        "4-2",
        1.5,
        has(
            mk,
            "sensor-consumer",
            "sensor-alert-consumer",
            'runtime          = "python3.14"',
        )
        and has(sensor_py, "ALERT_TOPIC", "put_item")
        and has(alert_py, "SNS_TOPIC_ARN", "alert/"),
        "Sensor + alert Lambda python3.14",
    )
    add(
        "4-3",
        1.5,
        has(
            mk,
            "msk-cluster",
            'kafka_version          = "3.6.0"',
            'instance_type   = "kafka.t3.small"',
            "iam = true",
        ),
        "MSK cluster 3.6.0 kafka.t3.small + IAM auth",
    )
    add(
        "4-4",
        1.5,
        has(
            mk,
            "aws_lambda_event_source_mapping",
            "local.raw_topic",
            "local.alert_topic",
            "event_source_arn = aws_msk_cluster.this.arn",
        )
        and has(mk, 'raw_topic         = "${local.name_prefix}-sensor-raw"', 'alert_topic       = "${local.name_prefix}-sensor-alert"'),
        "MSK → Lambda event source mappings",
    )
    add(
        "4-5-A",
        0.5,
        has(sensor_py, '"status": "NORMAL"', "temperature", "put_item")
        and (
            re.search(r"temperature\s*>\s*80", sensor_py) is not None
            or re.search(r"temp\s*>\s*80", sensor_py) is not None
        ),
        "Sensor consumer writes NORMAL to DDB + alert thresholds",
    )
    add(
        "4-5-B",
        0.5,
        has(mk, "sensor-producer", "user_data")
        and has(mk_ud, "sensor-producer.service", "TOPIC_RAW=wsc2026-sensor-raw", "BOOTSTRAP_SERVERS", "systemctl enable --now sensor-producer"),
        "Producer EC2 systemd continuous publish",
    )

    # Multi-region providers
    add(
        "0-providers",
        0.0,
        has(
            main_tf,
            'region = "ap-southeast-1"',
            'region = "ap-northeast-2"',
            'region = "eu-west-1"',
            'region = "ap-northeast-1"',
            'source = "./modules/workflow"',
            'source = "./modules/analytics"',
            'source = "./modules/event"',
            'source = "./modules/msk"',
        ),
        "4-region providers + modules (info)",
    )

    scored = [r for r in rows if r[1] > 0]
    total = sum(p for _, p, s, _ in scored if s == "PASS")
    maxt = sum(p for _, p, _, _ in scored)
    pct = round(total / maxt * 100) if maxt else 0

    print("=== day2/002 채점 시뮬레이션 (mark2-*.sh 기준) ===\n")
    for id_, pts, st, reason in rows:
        if pts == 0:
            print(f"[INFO] {id_} — {reason}")
            continue
        print(f"[{st}] {id_} {pts} — {reason}")
    print(f"\n합계: {total}/{maxt} = {pct}점")
    fails = [x for x in scored if x[2] == "FAIL"]
    if fails:
        print("\n감점:")
        for id_, pts, _, reason in fails:
            print(f"  - {id_} (-{pts}): {reason}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
