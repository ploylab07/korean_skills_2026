data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name = "wsi-bastion-eip"
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public["a"].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euxo pipefail
    yum update -y
    yum install -y awscli curl
    EOF
  )

  tags = {
    Name = "wsi-bastion"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
