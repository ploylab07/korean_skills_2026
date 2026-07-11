# Hub VPC
resource "aws_vpc" "hub" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = "wsc-hub-vpc" })
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
  tags   = merge(local.tags, { Name = "wsc-hub-igw" })
}

resource "aws_subnet" "hub_pub_a" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "wsc-hub-sn-pub-a" })
}

resource "aws_subnet" "hub_pub_c" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az_c
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "wsc-hub-sn-pub-c" })
}

resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }
  tags = merge(local.tags, { Name = "wsc-hub-rt-public" })
}

resource "aws_route_table_association" "hub_pub_a" {
  subnet_id      = aws_subnet.hub_pub_a.id
  route_table_id = aws_route_table.hub_public.id
}

resource "aws_route_table_association" "hub_pub_c" {
  subnet_id      = aws_subnet.hub_pub_c.id
  route_table_id = aws_route_table.hub_public.id
}

# Spoke VPC
resource "aws_vpc" "spoke" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = "wsc-spoke-vpc" })
}

resource "aws_internet_gateway" "spoke" {
  vpc_id = aws_vpc.spoke.id
  tags   = merge(local.tags, { Name = "wsc-spoke-igw" })
}

resource "aws_subnet" "spoke_pub_a" {
  vpc_id                  = aws_vpc.spoke.id
  cidr_block              = "192.168.0.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "wsc-spoke-sn-pub-a" })
}

resource "aws_subnet" "spoke_pub_c" {
  vpc_id                  = aws_vpc.spoke.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = local.az_c
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "wsc-spoke-sn-pub-c" })
}

resource "aws_subnet" "spoke_priv_a" {
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = local.az_a
  tags              = merge(local.tags, { Name = "wsc-spoke-sn-priv-a" })
}

resource "aws_subnet" "spoke_priv_c" {
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = "192.168.3.0/24"
  availability_zone = local.az_c
  tags              = merge(local.tags, { Name = "wsc-spoke-sn-priv-c" })
}

resource "aws_eip" "spoke_nat_a" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "wsc-spoke-nat-a-eip" })
}

resource "aws_eip" "spoke_nat_c" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "wsc-spoke-nat-c-eip" })
}

resource "aws_nat_gateway" "spoke_a" {
  allocation_id = aws_eip.spoke_nat_a.id
  subnet_id     = aws_subnet.spoke_pub_a.id
  tags          = merge(local.tags, { Name = "wsc-spoke-nat-a" })
  depends_on    = [aws_internet_gateway.spoke]
}

resource "aws_nat_gateway" "spoke_c" {
  allocation_id = aws_eip.spoke_nat_c.id
  subnet_id     = aws_subnet.spoke_pub_c.id
  tags          = merge(local.tags, { Name = "wsc-spoke-nat-c" })
  depends_on    = [aws_internet_gateway.spoke]
}

resource "aws_route_table" "spoke_public" {
  vpc_id = aws_vpc.spoke.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.spoke.id
  }
  tags = merge(local.tags, { Name = "wsc-spoke-rt-public" })
}

resource "aws_route_table" "spoke_private_a" {
  vpc_id = aws_vpc.spoke.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.spoke_a.id
  }
  tags = merge(local.tags, { Name = "wsc-spoke-rt-priv-a" })
}

resource "aws_route_table" "spoke_private_c" {
  vpc_id = aws_vpc.spoke.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.spoke_c.id
  }
  tags = merge(local.tags, { Name = "wsc-spoke-rt-priv-c" })
}

resource "aws_route_table_association" "spoke_pub_a" {
  subnet_id      = aws_subnet.spoke_pub_a.id
  route_table_id = aws_route_table.spoke_public.id
}

resource "aws_route_table_association" "spoke_pub_c" {
  subnet_id      = aws_subnet.spoke_pub_c.id
  route_table_id = aws_route_table.spoke_public.id
}

resource "aws_route_table_association" "spoke_priv_a" {
  subnet_id      = aws_subnet.spoke_priv_a.id
  route_table_id = aws_route_table.spoke_private_a.id
}

resource "aws_route_table_association" "spoke_priv_c" {
  subnet_id      = aws_subnet.spoke_priv_c.id
  route_table_id = aws_route_table.spoke_private_c.id
}

resource "aws_security_group" "hub_bastion" {
  name        = "wsc-hub-bastion-sg"
  description = "Hub bastion"
  vpc_id      = aws_vpc.hub.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "wsc-hub-bastion-sg" })
}

resource "aws_security_group" "app" {
  name        = "wsc-spoke-app-sg"
  description = "Spoke application servers"
  vpc_id      = aws_vpc.spoke.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "wsc-spoke-app-sg" })
}

resource "aws_security_group" "alb" {
  name        = "wsc-spoke-alb-sg"
  description = "Internal ALB"
  vpc_id      = aws_vpc.spoke.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.spoke.cidr_block, aws_vpc.hub.cidr_block]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "wsc-spoke-alb-sg" })
}
