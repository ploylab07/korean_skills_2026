apiVersion: v1
kind: Namespace
metadata:
  name: wsc
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: v1
kind: Namespace
metadata:
  name: logging
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: wsc-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  encrypted: "true"
  kmsKeyId: ${KMS_KEY_ARN}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: wsc-config
  namespace: wsc
data:
  AWS_REGION: ${REGION}
  TABLE_NAME: ${TABLE_NAME}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: wsc-sa
  namespace: wsc
  annotations:
    eks.amazonaws.com/role-arn: ${APP_POD_ROLE_ARN}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluent-bit
  namespace: logging
  annotations:
    eks.amazonaws.com/role-arn: ${FLUENT_BIT_ROLE_ARN}
