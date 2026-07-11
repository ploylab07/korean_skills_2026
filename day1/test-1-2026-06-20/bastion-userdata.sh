#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

ARTIFACTS_BUCKET="${artifacts_bucket}"

# SSH port 2222
sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2222/' /etc/ssh/sshd_config
systemctl restart sshd

# Packages
dnf install -y docker git jq mysql
systemctl enable --now docker
usermod -aG docker ec2-user

# AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -qo /tmp/awscliv2.zip -d /tmp && /tmp/aws/install --update

# kubectl
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# eksctl
curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl-$(uname -s)_amd64.tar.gz"
tar -xzf eksctl-$(uname -s)_amd64.tar.gz -C /usr/local/bin && rm eksctl-$(uname -s)_amd64.tar.gz

# argo rollouts kubectl plugin
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64 && mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Download artifacts from S3
aws s3 cp "s3://${artifacts_bucket}/marking.sh" /home/ec2-user/marking.sh --region ${region}
aws s3 cp "s3://${artifacts_bucket}/day1_table_v1.sql" /tmp/day1_table_v1.sql --region ${region}
aws s3 cp "s3://${artifacts_bucket}/red_1.0.0" /tmp/red_1.0.0 --region ${region}
aws s3 cp "s3://${artifacts_bucket}/green_1.0.0" /tmp/green_1.0.0 --region ${region}
aws s3 cp "s3://${artifacts_bucket}/red_1.0.1" /tmp/red_1.0.1 --region ${region}
aws s3 cp "s3://${artifacts_bucket}/green_1.0.1" /tmp/green_1.0.1 --region ${region}
chown ec2-user:ec2-user /home/ec2-user/marking.sh
chmod +x /home/ec2-user/marking.sh

# GitHub repository setup
sudo -u ec2-user bash <<SETUP
set -euxo pipefail
cd /home/ec2-user
git config --global user.email "ec2-user@gj2025.local"
git config --global user.name "ec2-user"

if [ ! -d gj2025-repository/.git ]; then
  rm -rf gj2025-repository
  git clone https://${github_token}@github.com/${github_owner}/${github_repo}.git gj2025-repository || \
    (mkdir -p gj2025-repository && cd gj2025-repository && git init)
fi

cd /home/ec2-user/gj2025-repository

setup_app_branch() {
  local branch=\$1 app=\$2 binary=\$3
  git checkout -B "\$branch"
  rm -f red green
  cp "\$binary" "\$app"
  chmod +x "\$app"
  cat > Dockerfile <<EOF
FROM alpine:3.19
WORKDIR /app
COPY \$app /app/\$app
EXPOSE 8080
ENTRYPOINT ["/app/\$app"]
EOF
  cat > buildspec.yaml <<EOF
version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${region}.amazonaws.com
  build:
    commands:
      - docker build -t \$REPOSITORY_URI:latest .
      - docker tag \$REPOSITORY_URI:latest \$REPOSITORY_URI:\$CODEBUILD_RESOLVED_SOURCE_VERSION
  post_build:
    commands:
      - docker push \$REPOSITORY_URI:latest
      - docker push \$REPOSITORY_URI:\$CODEBUILD_RESOLVED_SOURCE_VERSION
artifacts:
  files: []
EOF
  git add "\$app" Dockerfile buildspec.yaml
  git commit -m "init \$branch" || true
}

setup_app_branch app-red red /tmp/red_1.0.0
setup_app_branch app-green green /tmp/green_1.0.0

for branch in gitops-red gitops-green; do
  git checkout -B "\$branch"
  mkdir -p manifests
  echo "# gitops \$branch" > manifests/README.md
  git add . && git commit -m "init \$branch" || true
done

git remote set-url origin https://${github_token}@github.com/${github_owner}/${github_repo}.git || true
git push -u origin app-red gitops-red app-green gitops-green --force || true
SETUP

# Wait for EKS
for i in \$(seq 1 90); do
  if aws eks describe-cluster --name ${cluster_name} --region ${region} --query 'cluster.status' --output text 2>/dev/null | grep -q ACTIVE; then
    aws eks update-kubeconfig --name ${cluster_name} --region ${region}
    break
  fi
  sleep 30
done

# Build and push initial images to ECR
ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin \$ACCOUNT_ID.dkr.ecr.${region}.amazonaws.com

for app in red green; do
  cd /home/ec2-user/gj2025-repository
  git checkout app-\$app
  docker build -t \$ACCOUNT_ID.dkr.ecr.${region}.amazonaws.com/\$app:latest .
  docker push \$ACCOUNT_ID.dkr.ecr.${region}.amazonaws.com/\$app:latest
done

echo "Bastion setup complete"
