#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

PASSWORD="${password}"

# SSH password authentication
echo "root:$PASSWORD" | chpasswd
echo "ec2-user:$PASSWORD" | chpasswd
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# marking directory for 채점 (early — required for grading access)
mkdir -p /home/ec2-user/marking
cat > /home/ec2-user/marking/mark.sh <<'MARK'
#!/bin/bash
echo "mark.sh placeholder - run official marking script here"
MARK
chmod +x /home/ec2-user/marking/mark.sh
chown -R ec2-user:ec2-user /home/ec2-user/marking

# Packages (curl-minimal is preinstalled on AL2023)
dnf install -y jq iputils docker sshpass unzip --allowerasing
systemctl enable --now docker
usermod -aG docker ec2-user

# AWS CLI v2
curl -fsS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -qo /tmp/awscliv2.zip -d /tmp && /tmp/aws/install --update
aws configure set default.region ${region}
aws configure set default.output json

# kubectl
curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# eksctl (optional)
curl -fsSLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" || true
if [ -f eksctl_Linux_amd64.tar.gz ]; then
  tar -xzf eksctl_Linux_amd64.tar.gz -C /usr/local/bin
  rm -f eksctl_Linux_amd64.tar.gz
fi

# Build and push Docker image
mkdir -p /opt/wsc
for i in $(seq 1 60); do
  if aws s3 cp "s3://${static_bucket}/artifacts/book" /opt/wsc/book --region ${region}; then
    break
  fi
  sleep 30
done
aws s3 cp "s3://${static_bucket}/static/" /opt/wsc/static/ --recursive --region ${region} || true

cat > /opt/wsc/Dockerfile <<'DOCKERFILE'
FROM scratch
COPY book /book
EXPOSE 8080
ENTRYPOINT ["/book"]
DOCKERFILE

cat > /home/ec2-user/build-image.sh <<BUILDSCRIPT
#!/bin/bash
set -euo pipefail
cd /opt/wsc
aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${ecr_repo}
docker build -t ${ecr_repo}:v1.0.0 .
docker push ${ecr_repo}:v1.0.0
BUILDSCRIPT
chmod +x /home/ec2-user/build-image.sh
chown ec2-user:ec2-user /home/ec2-user/build-image.sh

# EKS kubeconfig helper
cat > /home/ec2-user/update-kubeconfig.sh <<KCFG
#!/bin/bash
aws eks update-kubeconfig --region ${region} --name ${cluster_name}
KCFG
chmod +x /home/ec2-user/update-kubeconfig.sh
chown ec2-user:ec2-user /home/ec2-user/update-kubeconfig.sh
