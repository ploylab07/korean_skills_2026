import os

import boto3

ssm = boto3.client("ssm")

INSTANCE_ID = os.environ["INSTANCE_ID"]
PARAM_NAME = os.environ["PARAM_NAME"]


def _run_shell(script: str) -> str:
    resp = ssm.send_command(
        InstanceIds=[INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [script]},
        TimeoutSeconds=60,
    )
    cmd_id = resp["Command"]["CommandId"]
    waiter = ssm.get_waiter("command_executed")
    waiter.wait(CommandId=cmd_id, InstanceId=INSTANCE_ID, WaiterConfig={"Delay": 2, "MaxAttempts": 30})
    out = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=INSTANCE_ID)
    return out.get("StandardOutputContent", "")


def handler(event, context):
    health = _run_shell("curl -sf http://127.0.0.1:8080/health >/dev/null && echo OK || echo FAIL")
    if "OK" not in health:
        return {"status": "skip", "reason": "unhealthy"}

    # Match scoring script: sed 's/[[:space:]]*$//' then compare
    current = _run_shell("sed 's/[[:space:]]*$//' /home/ec2-user/app.py").rstrip()
    backup = ssm.get_parameter(Name=PARAM_NAME)["Parameter"]["Value"].rstrip()

    if current == backup:
        return {"status": "noop"}

    ssm.put_parameter(Name=PARAM_NAME, Value=current, Type="String", Overwrite=True)
    return {"status": "updated"}
