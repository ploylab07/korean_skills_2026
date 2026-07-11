#!/bin/bash
set -euxo pipefail

PASSWORD="${node_password}"
echo "ec2-user:$PASSWORD" | chpasswd
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
dnf install -y curl iputils
systemctl restart sshd || true

cat > /etc/eks/node-config.yaml <<EOF
---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${cluster_name}
    apiServerEndpoint: ${api_endpoint}
    certificateAuthority: ${cluster_ca}
  kubelet:
    config:
      clusterDomain: ${cluster_domain}
EOF

/opt/aws/bin/nodeadm init -c file:///etc/eks/node-config.yaml || \
  /etc/eks/bootstrap.sh ${cluster_name} --kubelet-extra-args '--cluster-domain=${cluster_domain}'
