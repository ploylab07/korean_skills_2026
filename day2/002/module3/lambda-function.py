import json
import os
from datetime import datetime, timezone

import boto3

ec2_client = boto3.client("ec2")
iam_client = boto3.client("iam")
sns_client = boto3.client("sns")
config_client = boto3.client("config")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def publish_alert(event_type, detail, action):
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps({
            "event": event_type,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "detail": detail,
            "action": action,
        }),
    )


# ===== wsc2026-sg-remediation =====
def sg_remediation_handler(event, context):
    sg_id = os.environ.get("SECURITY_GROUP_ID")
    detail = event.get("detail", {})
    request_params = detail.get("requestParameters", {})

    # CloudTrail / EventBridge 형식과 Config 형식 모두 처리
    ip_permissions = request_params.get("ipPermissions")
    if isinstance(ip_permissions, dict) and "items" in ip_permissions:
        items = ip_permissions["items"]
        for item in items:
            ip_ranges = item.get("ipRanges", {})
            ranges = ip_ranges.get("items", []) if isinstance(ip_ranges, dict) else ip_ranges
            cidr_list = []
            for r in ranges or []:
                if isinstance(r, dict):
                    cidr_list.append({"CidrIp": r.get("cidrIp", "0.0.0.0/0")})
                else:
                    cidr_list.append({"CidrIp": str(r)})
            try:
                ec2_client.revoke_security_group_ingress(
                    GroupId=request_params.get("groupId") or sg_id,
                    IpPermissions=[{
                        "IpProtocol": item.get("ipProtocol", "tcp"),
                        "FromPort": int(item.get("fromPort", 22)),
                        "ToPort": int(item.get("toPort", 22)),
                        "IpRanges": cidr_list or [{"CidrIp": "0.0.0.0/0"}],
                    }],
                )
            except Exception as e:
                print(f"revoke failed: {e}")
    else:
        # fallback: remove all inbound rules on target SG
        target_sg = request_params.get("groupId") or sg_id
        try:
            sg = ec2_client.describe_security_groups(GroupIds=[target_sg])["SecurityGroups"][0]
            if sg.get("IpPermissions"):
                ec2_client.revoke_security_group_ingress(
                    GroupId=target_sg,
                    IpPermissions=sg["IpPermissions"],
                )
        except Exception as e:
            print(f"fallback revoke failed: {e}")

    publish_alert(
        "SG_INBOUND_ADDED",
        f"Unauthorized inbound rule removed from {sg_id}",
        "RESTORED",
    )


# ===== wsc2026-role-remediation =====
def role_remediation_handler(event, context):
    instance_id = os.environ.get("INSTANCE_ID")
    role_name = os.environ.get("ROLE_NAME")
    detail = event.get("detail", {})

    associations = ec2_client.describe_iam_instance_profile_associations(
        Filters=[{"Name": "instance-id", "Values": [instance_id]}]
    ).get("IamInstanceProfileAssociations", [])

    for assoc in associations:
        if assoc.get("State") in ("associated", "associating"):
            ec2_client.replace_iam_instance_profile_association(
                AssociationId=assoc["AssociationId"],
                IamInstanceProfile={"Name": role_name},
            )

    publish_alert(
        "ROLE_CHANGED",
        f"IAM role on instance {instance_id} was changed and restored to {role_name}",
        "RESTORED",
    )


# ===== wsc2026-ec2-terminate-alert =====
def ec2_terminate_handler(event, context):
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id", "unknown")

    publish_alert(
        "EC2_TERMINATED",
        f"EC2 instance {instance_id} was terminated",
        "ALERT_ONLY",
    )


# ===== wsc2026-ec2-type-remediation =====
def ec2_type_remediation_handler(event, context):
    instance_id = os.environ.get("INSTANCE_ID")
    original_type = os.environ.get("INSTANCE_TYPE")
    detail = event.get("detail", {})

    ec2_client.stop_instances(InstanceIds=[instance_id])
    waiter = ec2_client.get_waiter("instance_stopped")
    waiter.wait(InstanceIds=[instance_id])
    ec2_client.modify_instance_attribute(
        InstanceId=instance_id,
        InstanceType={"Value": original_type},
    )
    ec2_client.start_instances(InstanceIds=[instance_id])

    publish_alert(
        "EC2_TYPE_CHANGED",
        f"Instance {instance_id} type was changed and restored to {original_type}",
        "RESTORED",
    )


# ===== wsc2026-ec2-stop-remediation (채점 스크립트용) =====
def ec2_stop_remediation_handler(event, context):
    instance_id = os.environ.get("INSTANCE_ID")
    detail = event.get("detail", {})
    state = detail.get("state", "")
    event_instance = detail.get("instance-id") or instance_id

    if state and state not in ("stopped", "stopping"):
        return {"status": "ignored"}

    target = event_instance or instance_id
    try:
        ec2_client.start_instances(InstanceIds=[target])
    except Exception as e:
        print(f"start failed: {e}")

    publish_alert(
        "EC2_STOPPED",
        f"EC2 instance {target} was stopped and restarted",
        "RESTORED",
    )


# ===== wsc2026-tag-alert (채점 스크립트용) =====
def tag_alert_handler(event, context):
    detail = event.get("detail", event)
    resource_id = (
        detail.get("resourceId")
        or detail.get("configurationItem", {}).get("resourceId")
        or "unknown"
    )
    publish_alert(
        "TAG_NON_COMPLIANT",
        f"Resource {resource_id} is missing required tags",
        "ALERT_ONLY",
    )
