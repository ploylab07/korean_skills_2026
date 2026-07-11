resource "aws_security_group" "bastion" {
  name        = "${local.prefix}-bastion-sg"
  description = "Bastion SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-bastion-sg" })
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.prefix}-bastion-eip" })
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true
  user_data_replace_on_change = true
  user_data = base64encode(templatefile("${path.module}/bastion-userdata.sh", {
    region        = var.region
    cluster_name  = "${local.prefix}-eks-cluster"
    password      = local.bastion_password
    ecr_repo      = aws_ecr_repository.main.repository_url
    static_bucket = "${local.prefix}-static-${data.aws_caller_identity.current.account_id}"
  }))

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
  }

  tags = merge(local.common_tags, { Name = "${local.prefix}-bastion" })

  depends_on = [aws_nat_gateway.main]
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
