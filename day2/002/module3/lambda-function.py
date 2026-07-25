import json
import os
from datetime import datetime, timezone

import boto3

ec2_client = boto3.client("ec2")
sns_client = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def publish_alert(event_type, detail, action):
    """Publish an operational notification when a topic is configured."""
    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN is not configured; alert not published")
        return

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps({
            "event": event_type,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "detail": detail,
            "action": action,
        }),
    )


def sg_remediation_handler(event, context):
    """Remove every ingress rule from the protected security group."""
    sg_id = os.environ.get("SECURITY_GROUP_ID")
    if not sg_id:
        raise ValueError("SECURITY_GROUP_ID is required")

    # Always use the configured group.  The EventBridge rule sees account-wide
    # CloudTrail events, so trusting a group ID supplied by the event could
    # accidentally alter an unrelated security group.
    sg = ec2_client.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]
    permissions = sg.get("IpPermissions", [])
    if permissions:
        ec2_client.revoke_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=permissions,
        )

    publish_alert(
        "SG_INBOUND_ADDED",
        f"Unauthorized inbound rule removed from {sg_id}",
        "RESTORED",
    )
    return {"status": "remediated", "security_group_id": sg_id}


def ec2_terminate_handler(event, context):
    """Send an alert only; a terminated instance is never recreated."""
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id", "unknown")

    publish_alert(
        "EC2_TERMINATED",
        f"EC2 instance {instance_id} was terminated",
        "ALERT_ONLY",
    )
    return {"status": "alerted", "instance_id": instance_id}


def ec2_stop_remediation_handler(event, context):
    """Restart the configured instance after its stopped-state event."""
    instance_id = os.environ.get("INSTANCE_ID")
    detail = event.get("detail", {})
    state = detail.get("state")

    if state != "stopped":
        return {"status": "ignored"}

    if not instance_id:
        raise ValueError("INSTANCE_ID is required")
    ec2_client.start_instances(InstanceIds=[instance_id])

    publish_alert(
        "EC2_STOPPED",
        f"EC2 instance {instance_id} was stopped and restarted",
        "RESTORED",
    )
    return {"status": "restart_requested", "instance_id": instance_id}


def tag_alert_handler(event, context):
    """Alert on a Config non-compliance event."""
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
    return {"status": "alerted", "resource_id": resource_id}
