resource "tls_private_key" "bastion" {
  count     = var.bastion_key_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  count      = var.bastion_key_name == "" ? 1 : 0
  key_name   = "wsc-scaling-bastion-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.bastion[0].public_key_openssh
}

locals {
  key_name = var.bastion_key_name != "" ? var.bastion_key_name : aws_key_pair.bastion[0].key_name
}

resource "aws_iam_role" "bastion" {
  name = "wsc-scaling-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "wsc-scaling-bastion-profile"
  role = aws_iam_role.bastion.name
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "wsc-scaling-bastion-eip" })
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.pub_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  key_name                    = local.key_name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker
    systemctl enable --now docker
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key" | rpm --import - 2>/dev/null || true
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp && /tmp/aws/install
    aws eks update-kubeconfig --region ap-northeast-2 --name wsc-scaling-cluster || true
  EOF
  )

  tags = merge(local.tags, { Name = "wsc-scaling-bastion" })

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
