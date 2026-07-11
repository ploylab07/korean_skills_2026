apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: wsc-scaling-trigger-auth
  namespace: wsc-scaling
spec:
  podIdentity:
    provider: aws
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: wsc-scaling-scaledobject
  namespace: wsc-scaling
spec:
  scaleTargetRef:
    name: wsc-scaling-deploy
  minReplicaCount: 2
  pollingInterval: 30
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: wsc-scaling-trigger-auth
      metadata:
        queueURL: ${sqs_url}
        queueLength: "5"
        awsRegion: ap-northeast-2
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: wsc-scaling-nodeclass
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  role: ${karpenter_node_role}
  subnetSelectorTerms:
    - tags:
        Name: wsc-scaling-sn-priv-a
    - tags:
        Name: wsc-scaling-sn-priv-c
  securityGroupSelectorTerms:
    - tags:
        Name: wsc-scaling-eks-nodes-sg
  tags:
    Name: wsc-scaling-node
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: wsc-scaling-nodepool
spec:
  template:
    metadata:
      labels:
        dedicated: scaling
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: wsc-scaling-nodeclass
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large", "t3.xlarge"]
  limits:
    cpu: "100"
    memory: 200Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
