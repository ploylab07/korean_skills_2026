resource "aws_key_pair" "bastion" {
  key_name   = var.bastion_key_name
  public_key = tls_private_key.bastion.public_key_openssh
}

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_eip" "bastion" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-eip" })
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Bastion SSH on port 2222"
  vpc_id      = aws_vpc.hub.id

  ingress {
    description = "SSH"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = [var.bastion_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-sg" })
}

resource "aws_iam_role" "bastion" {
  name = "${local.name_prefix}-bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "bastion_admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
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

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.hub_public_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  key_name                    = aws_key_pair.bastion.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true
  user_data = base64encode(templatefile("${path.module}/bastion-userdata.sh", {
    region           = var.region
    cluster_name     = "${local.name_prefix}-eks-cluster"
    github_owner     = var.github_owner
    github_repo      = var.github_repo
    github_token     = var.github_token
    artifacts_bucket = aws_s3_bucket.artifacts.id
    rds_proxy_name   = "${local.name_prefix}-rds-proxy"
    db_password      = var.db_password
  }))

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion" })

  depends_on = [
    aws_nat_gateway.hub,
    aws_s3_object.marking_sh,
    aws_s3_object.red_binary,
    aws_s3_object.green_binary,
  ]
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

resource "aws_ssm_parameter" "bastion_private_key" {
  name        = "/${local.name_prefix}/bastion/private-key"
  description = "Bastion SSH private key"
  type        = "SecureString"
  value       = tls_private_key.bastion.private_key_pem
  tags        = local.common_tags
}
