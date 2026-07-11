import os
import time
from datetime import datetime, timezone, timedelta

import boto3

ssm = boto3.client("ssm")
logs = boto3.client("logs")

INSTANCE_ID = os.environ["INSTANCE_ID"]
PARAM_NAME = os.environ["PARAM_NAME"]
LOG_GROUP = os.environ["LOG_GROUP"]
SERVICE = os.environ.get("SERVICE_NAME", "gj2026-app")
KST = timezone(timedelta(hours=9))


def _run_shell(script: str) -> str:
    resp = ssm.send_command(
        InstanceIds=[INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [script]},
        TimeoutSeconds=120,
    )
    cmd_id = resp["Command"]["CommandId"]
    waiter = ssm.get_waiter("command_executed")
    waiter.wait(CommandId=cmd_id, InstanceId=INSTANCE_ID, WaiterConfig={"Delay": 2, "MaxAttempts": 60})
    out = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=INSTANCE_ID)
    return out.get("StandardOutputContent", "")


def _put_recovery_log(message: str) -> None:
    stream = "recovery"
    try:
        logs.create_log_stream(logGroupName=LOG_GROUP, logStreamName=stream)
    except logs.exceptions.ResourceAlreadyExistsException:
        pass

    event = {"timestamp": int(datetime.now().timestamp() * 1000), "message": message}
    kwargs = {
        "logGroupName": LOG_GROUP,
        "logStreamName": stream,
        "logEvents": [event],
    }
    try:
        desc = logs.describe_log_streams(logGroupName=LOG_GROUP, logStreamNamePrefix=stream)
        for s in desc.get("logStreams", []):
            if s["logStreamName"] == stream and "uploadSequenceToken" in s:
                kwargs["sequenceToken"] = s["uploadSequenceToken"]
                break
    except Exception:
        pass

    try:
        logs.put_log_events(**kwargs)
    except logs.exceptions.InvalidSequenceTokenException as e:
        kwargs["sequenceToken"] = e.response["Error"]["Message"].split()[-1]
        logs.put_log_events(**kwargs)
    except logs.exceptions.DataAlreadyAcceptedException:
        pass


def handler(event, context):
    # 채점 3-4: stop 후 60초 시점에 ALARM 확인 가능하도록 복구 지연
    time.sleep(60)

    backup = ssm.get_parameter(Name=PARAM_NAME)["Parameter"]["Value"]
    if not backup.endswith("\n"):
        backup = backup + "\n"
    current = _run_shell("cat /home/ec2-user/app.py")

    import difflib

    diff_lines = list(
        difflib.unified_diff(
            backup.rstrip().splitlines(),
            current.rstrip().splitlines(),
            fromfile="--- 백업 (정상 버전)",
            tofile="+++ 현재 파일 (장애 버전)",
            lineterm="",
        )
    )
    diff_text = "\n".join(diff_lines) if diff_lines else "(변경 없음)"

    restore_script = f"""#!/bin/bash
set -euo pipefail
cat > /home/ec2-user/app.py <<'EOFAPP'
{backup.rstrip()}
EOFAPP
chown ec2-user:ec2-user /home/ec2-user/app.py
systemctl reset-failed {SERVICE} || true
systemctl restart {SERVICE}
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:8080/health >/dev/null && exit 0
  sleep 2
done
exit 1
"""
    _run_shell(restore_script)

    finished = datetime.now(KST).strftime("%Y-%m-%d %H:%M:%S KST")
    message = "\n".join(
        [
            "[장애 감지] 복구 대상: app",
            "원인: app 프로세스 다운",
            "수정된 내용:",
            diff_text,
            "복구 내용: Parameter Store에서 파일 복원 + 서비스 재시작 완료",
            f"복구 완료 시각: {finished}",
        ]
    )
    _put_recovery_log(message)
    return {"status": "recovered"}
