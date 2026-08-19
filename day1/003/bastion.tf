data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "wsc2026-bastion-sg"
  description = "Bastion host for private EKS access via SSM"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wsc2026-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.hub_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id, aws_security_group.mark.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y python3 unzip jq tar gzip
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.32.2/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp && /tmp/aws/install -u || true
    mkdir -p /root/.kube /home/ec2-user/.kube
    aws eks update-kubeconfig --region ${var.region} --name ${local.cluster_name} || true
    cp -a /root/.kube/config /home/ec2-user/.kube/config || true
    chown -R ec2-user:ec2-user /home/ec2-user/.kube || true
  EOF

  tags = {
    Name = "wsc2026-bastion"
  }

  depends_on = [aws_eks_cluster.main]
}
