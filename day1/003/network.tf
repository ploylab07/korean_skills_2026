resource "aws_vpc" "main" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wsc2026-skills-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wsc2026-skills-igw"
  }
}

resource "aws_subnet" "hub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true

  tags = {
    Name                              = "wsc2026-skills-hub-sub-a"
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "hub_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.10.0/24"
  availability_zone       = local.azs[1]
  map_public_ip_on_launch = true

  tags = {
    Name                              = "wsc2026-skills-hub-sub-b"
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = local.azs[0]

  tags = {
    Name                                      = "wsc2026-skills-app-sub-a"
    "kubernetes.io/role/internal-elb"         = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.20.0/24"
  availability_zone = local.azs[1]

  tags = {
    Name                                      = "wsc2026-skills-app-sub-b"
    "kubernetes.io/role/internal-elb"         = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_eip" "nat_a" {
  domain = "vpc"

  tags = {
    Name = "wsc2026-skills-nat-a-eip"
  }
}

resource "aws_eip" "nat_b" {
  domain = "vpc"

  tags = {
    Name = "wsc2026-skills-nat-b-eip"
  }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.hub_a.id

  tags = {
    Name = "wsc2026-skills-nat-a"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.hub_b.id

  tags = {
    Name = "wsc2026-skills-nat-b"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "hub" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "wsc2026-skills-hub-rtb"
  }
}

resource "aws_route_table" "app_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }

  tags = {
    Name = "wsc2026-skills-app-rtb-a"
  }
}

resource "aws_route_table" "app_b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }

  tags = {
    Name = "wsc2026-skills-app-rtb-b"
  }
}

resource "aws_route_table_association" "hub_a" {
  subnet_id      = aws_subnet.hub_a.id
  route_table_id = aws_route_table.hub.id
}

resource "aws_route_table_association" "hub_b" {
  subnet_id      = aws_subnet.hub_b.id
  route_table_id = aws_route_table.hub.id
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.app_a.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.app_b.id
}

resource "aws_security_group" "mark" {
  name        = "mark-sg"
  description = "Security group for CloudShell grading"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mark-sg"
  }
}

resource "aws_security_group" "alb" {
  name        = "wsc2026-app-alb-sg"
  description = "ALB security group - CloudFront prefix list only"
  vpc_id      = aws_vpc.main.id

  # Only HTTP: CloudFront prefix list (~45 entries) fits under default 60 SG rules.
  # CloudFront origin uses http-only to this ALB.
  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wsc2026-app-alb-sg"
  }
}

resource "aws_security_group" "eks_cluster" {
  name        = "wsc2026-eks-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wsc2026-eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "wsc2026-eks-nodes-sg"
  description = "EKS worker nodes security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Node to node"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Cluster to nodes"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  ingress {
    description     = "Bastion to nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "ALB to nodes"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wsc2026-eks-nodes-sg"
  }
}

resource "aws_security_group_rule" "cluster_from_bastion" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "cluster_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

# EKS pods use the managed cluster SG — attach ALB rules there (not the unused custom SG).
resource "aws_security_group_rule" "cluster_sg_from_alb_8080" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to pods on 8080"
}

resource "aws_security_group_rule" "cluster_sg_from_alb_80" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to pods on 80"
}

resource "aws_security_group_rule" "cluster_sg_from_bastion" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.bastion.id
  description              = "Bastion to EKS API"
}

resource "aws_security_group_rule" "cluster_sg_from_mark" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.mark.id
  description              = "CloudShell mark-sg to EKS API"
}

resource "aws_security_group_rule" "cluster_sg_from_vpc_443" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  cidr_blocks       = [aws_vpc.main.cidr_block]
  description       = "VPC (CloudShell/bastion) to EKS API"
}

resource "aws_security_group_rule" "cluster_sg_grafana_3000" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Grafana NLB to pods"
}
