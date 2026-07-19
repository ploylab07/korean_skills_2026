resource "aws_vpc" "main" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "wskorea26-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "book-igw" }
}

resource "aws_subnet" "pub_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = local.az_c
  map_public_ip_on_launch = true
  tags                    = { Name = "wskorea26-pub-subnet-c" }
}

resource "aws_subnet" "pub_d" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.2.0/24"
  availability_zone       = local.az_d
  map_public_ip_on_launch = true
  tags                    = { Name = "wskorea26-pub-subnet-d" }
}

resource "aws_subnet" "priv_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.201.0/24"
  availability_zone = local.az_c
  tags              = { Name = "wskorea26-priv-subnet-c" }
}

resource "aws_subnet" "priv_d" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.202.0/24"
  availability_zone = local.az_d
  tags              = { Name = "wskorea26-priv-subnet-d" }
}

resource "aws_eip" "nat_c" {
  domain = "vpc"
  tags   = { Name = "book-ngw-c-eip" }
}

resource "aws_eip" "nat_d" {
  domain = "vpc"
  tags   = { Name = "book-ngw-d-eip" }
}

resource "aws_nat_gateway" "nat_c" {
  allocation_id = aws_eip.nat_c.id
  subnet_id     = aws_subnet.pub_c.id
  tags          = { Name = "book-ngw-c" }
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "nat_d" {
  allocation_id = aws_eip.nat_d.id
  subnet_id     = aws_subnet.pub_d.id
  tags          = { Name = "book-ngw-d" }
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wskorea26-public-rtb" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.pub_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_d" {
  subnet_id      = aws_subnet.pub_d.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_c" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wskorea26-private-rtb-c" }
}

resource "aws_route" "private_c_nat" {
  route_table_id         = aws_route_table.private_c.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_c.id
}

resource "aws_route_table_association" "priv_c" {
  subnet_id      = aws_subnet.priv_c.id
  route_table_id = aws_route_table.private_c.id
}

resource "aws_route_table" "private_d" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wskorea26-private-rtb-d" }
}

resource "aws_route" "private_d_nat" {
  route_table_id         = aws_route_table.private_d.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_d.id
}

resource "aws_route_table_association" "priv_d" {
  subnet_id      = aws_subnet.priv_d.id
  route_table_id = aws_route_table.private_d.id
}

resource "aws_security_group" "env" {
  name        = "wskorea26-vpc-environment-sg"
  description = "EKS/CloudShell access"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wskorea26-vpc-environment-sg" }

  ingress {
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

  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

resource "aws_security_group" "eks_cluster" {
  name        = "wskorea26-eks-cluster-sg"
  description = "EKS cluster SG"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wskorea26-eks-cluster-sg" }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.env.id]
  }

  ingress {
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

  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

resource "aws_security_group" "alb" {
  name        = "wskorea26-book-alb-sg"
  description = "Book ALB SG"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wskorea26-book-alb-sg" }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

resource "aws_security_group" "grafana_alb" {
  name        = "wskorea26-grafana-alb-sg"
  description = "Grafana ALB"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wskorea26-grafana-alb-sg" }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = [ingress, egress]
  }
}
