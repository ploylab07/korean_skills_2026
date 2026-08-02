#!/usr/bin/env python3
"""Simulate day2/008 grading from problem/score sheets + check_result + Terraform.

Usage:
  python3 simulate_grade.py
"""
from __future__ import annotations

import re
from pathlib import Path

BASE = Path(__file__).resolve().parent


def load(name: str) -> str:
    return (BASE / name).read_text(errors="replace")


def main() -> int:
    tf = {
        "m1": load("module1_docdb.tf"),
        "m2": load("module2_lattice.tf"),
        "m3": load("module3_ceh.tf"),
        "m4e": load("module4_eks.tf"),
        "wl": load("files/workloads.yaml.tftpl"),
        "k8s": load("module4_k8s.tf"),
    }
    res = {i: load(f"asgmt2_module{i}_check_result.txt") for i in range(1, 5)}
    rows: list[tuple[str, float, str, str]] = []

    def add(id_: str, pts: float, ok: bool, reason: str) -> None:
        rows.append((id_, pts, "PASS" if ok else "FAIL", reason))

    t, r = tf["m1"], res[1]
    add("1-1", 1.5, all(x in t for x in ["skills-nosql-docdb-cluster", "db.t3.medium", "alias/skills-nosql-docdb", "storage_encrypted"]) and "available" in r, "DocDB cluster/instance/KMS")
    add("1-2", 1.5, "skills-nosql-docdb-secret" in t and "skills-nosql-client-ec2" in r and "running" in r, "Secret + client EC2")
    add("1-3", 1.5, r.count("http_code=200") >= 2 and '"orders": 8' in r, "health/summary + data")
    add("1-4", 1.5, "expiresAt_ttl" in r and 'expireAfterSeconds": 0' in r, "indexes + TTL")
    add("1-5", 1.5, "O-1001" in r and r.count("http_code=200") >= 6, "query APIs")

    t, r = tf["m2"], res[2]
    add("2-1", 1.5, "10.61.0.0/16" in t and "10.62.0.0/16" in t and "skills-lattice-client-vpc" in r, "VPCs/CIDRs")
    add("2-2", 1.5, "skills-lattice-client-ec2" in r and "skills-lattice-service-ec2" in r and "http_code=200" in r, "EC2 + client health")
    add("2-3", 1.5, "skills-lattice-sn" in r and "ACTIVE" in r and "10.61.0.0/16" in t, "Lattice SN/assoc")
    sec24 = r.split("[2-5]")[0].split("[2-4]")[-1]
    add("2-4", 1.5, "HEALTHY" in sec24 and "PrefixListId" in sec24 and "0.0.0.0/0" not in sec24, "TG/listener/SG prefix-list")
    add("2-5", 1.5, "vpc-lattice" in r and "1001" in r and "http_code=200" in r, "E2E via lattice")

    t, r = tf["m3"], res[3]
    add("3-1", 1.5, "10.73.0.0/16" in t and "skills-ceh-protected-sg" in r, "VPC/EC2/SG")
    add("3-2", 1.5, '"Inbound": []' in r, "inbound empty")
    add("3-3", 1.5, "python3.12" in r and "PROTECTED_SECURITY_GROUP_ID" in r, "SNS/Lambda")
    add("3-4", 1.5, "AuthorizeSecurityGroupIngress" in r and "IsLogging" in r, "Trail/EventBridge")
    add("3-5", 1.5, "RESTORED" in r and "inbound_count=0" in r, "remediate")

    te, wl, k8s, r = tf["m4e"], tf["wl"], tf["k8s"], res[4]
    sec41 = r.split("[4-2]")[0]
    add("4-1", 1.25, "ACTIVE" in sec41 and "skills-sqs-fp-keda" in sec41 and "endpoint_public_access  = true" in te, "EKS+Fargate")
    sec42 = r.split("[4-3]")[0].split("[4-2]")[-1]
    add("4-2", 1.25, "keda-operator-role" in sec42 and "worker-role" in sec42, "SQS+IRSA")
    sec43 = r.split("[4-4]")[0].split("[4-3]")[-1]
    add("4-3", 1.25, "fargate-ip-" in sec43 and "keda-operator" in sec43 and "karpenter" in sec43, "controllers on Fargate")
    sec44 = r.split("[4-5]")[0].split("[4-4]")[-1]
    add("4-4", 1.25, "queueLength" in sec44 and "minReplicaCount: 0" in sec44 and "PROCESSING_SECONDS" in sec44, "worker/ScaledObject")

    sec45 = r.split("[4-6]")[0].split("[4-5]")[-1]
    node_lines = [ln for ln in sec45.splitlines() if "Ready" in ln and "fargate-ip-" not in ln and "compute.internal" in ln]
    long_keep = "consolidateAfter: 45m" in wl or "consolidateAfter: 45m" in k8s
    warm = "warmup" in k8s
    add(
        "4-5",
        1.25,
        ("skills-sqs-nodepool" in sec45 and "consolidationPolicy" in sec45 and "skills-sqs-nodeclass" in sec45)
        and (len(node_lines) >= 1 or (long_keep and warm)),
        f"NodePool/EC2NodeClass; Worker EC2 lines={len(node_lines)}; keep={long_keep} warm={warm}",
    )

    sec46 = r.split("[4-6]")[-1]
    running = bool(re.search(r"1/1\s+Running", sec46)) and any(x in sec46 for x in ("5/6", "6/6", "4/6", "3/6"))
    drain = bool(re.search(r"ApproximateNumberOfMessages\s+\|\s+0\s", sec46))
    add("4-6", 1.25, "sent=12" in sec46 and drain and running and "skills-sqs-nodepool-" in sec46, "scale-out + queue drain within window")

    total = sum(p for _, p, s, _ in rows if s == "PASS")
    maxt = sum(p for _, p, _, _ in rows)
    print("=== day2/008 채점 시뮬레이션 ===\n")
    for id_, pts, st, reason in rows:
        print(f"[{st}] {id_} {pts} — {reason}")
    print(f"\n합계: {total}/{maxt} = {round(total / maxt * 100)}점")
    fails = [x for x in rows if x[2] == "FAIL"]
    if fails:
        print("\n감점:")
        for id_, pts, _, reason in fails:
            print(f"  - {id_} (-{pts}): {reason}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
