resource "aws_vpc" "main" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "wsc2026-skills-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "wsc2026-skills-igw" })
}

resource "aws_subnet" "hub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "wsc2026-skills-hub-sub-a" })
}

resource "aws_subnet" "hub_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.10.0/24"
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "wsc2026-skills-hub-sub-b" })
}

resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = local.az_a
  tags = merge(local.common_tags, {
    Name                                                     = "wsc2026-skills-app-sub-a"
    "kubernetes.io/cluster/${local.cluster_name}"            = "shared"
    "kubernetes.io/role/internal-elb"                        = "1"
    "kubernetes.io/role/elb"                                 = "1"
  })
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.20.0/24"
  availability_zone = local.az_b
  tags = merge(local.common_tags, {
    Name                                                     = "wsc2026-skills-app-sub-b"
    "kubernetes.io/cluster/${local.cluster_name}"            = "shared"
    "kubernetes.io/role/internal-elb"                        = "1"
    "kubernetes.io/role/elb"                                 = "1"
  })
}

resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "wsc2026-skills-nat-a-eip" })
}

resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "wsc2026-skills-nat-b-eip" })
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.hub_a.id
  tags          = merge(local.common_tags, { Name = "wsc2026-skills-nat-a" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.hub_b.id
  tags          = merge(local.common_tags, { Name = "wsc2026-skills-nat-b" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "hub" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "wsc2026-skills-hub-rtb" })
}

resource "aws_route" "hub_igw" {
  route_table_id         = aws_route_table.hub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "hub_a" {
  subnet_id      = aws_subnet.hub_a.id
  route_table_id = aws_route_table.hub.id
}

resource "aws_route_table_association" "hub_b" {
  subnet_id      = aws_subnet.hub_b.id
  route_table_id = aws_route_table.hub.id
}

resource "aws_route_table" "app_a" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "wsc2026-skills-app-rtb-a" })
}

resource "aws_route" "app_a_nat" {
  route_table_id         = aws_route_table.app_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_a.id
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.app_a.id
}

resource "aws_route_table" "app_b" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "wsc2026-skills-app-rtb-b" })
}

resource "aws_route" "app_b_nat" {
  route_table_id         = aws_route_table.app_b.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_b.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.app_b.id
}

resource "aws_security_group" "bastion" {
  name        = "wsc2026-bastion-sg"
  description = "Bastion for EKS bootstrap"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "wsc2026-bastion-sg" })
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.hub_a.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.bastion.name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -q awscliv2.zip && ./aws/install
    EOF

  tags = merge(local.common_tags, { Name = "wsc2026-bastion" })
}
