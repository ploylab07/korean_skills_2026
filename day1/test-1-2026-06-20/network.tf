# ── Hub VPC ──────────────────────────────────────────────────────────────────

resource "aws_vpc" "hub" {
  cidr_block           = local.hub_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-hub-vpc" })
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-hub-igw" })
}

resource "aws_subnet" "hub_public_a" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-hub-public-subnet-a" })
}

resource "aws_subnet" "hub_public_b" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-hub-public-subnet-b" })
}

resource "aws_subnet" "hub_private_a" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.az_a
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-hub-private-subnet-a" })
}

resource "aws_subnet" "hub_private_b" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = local.az_b
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-hub-private-subnet-b" })
}

resource "aws_subnet" "hub_firewall" {
  vpc_id            = aws_vpc.hub.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = local.az_a
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-hub-firewall-subnet" })
}

resource "aws_eip" "hub_nat" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-hub-ngw-eip" })
}

resource "aws_nat_gateway" "hub" {
  allocation_id = aws_eip.hub_nat.id
  subnet_id     = aws_subnet.hub_firewall.id
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-hub-ngw" })

  depends_on = [aws_internet_gateway.hub]
}

# ── App VPC ──────────────────────────────────────────────────────────────────

resource "aws_vpc" "app" {
  cidr_block           = local.app_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-vpc" })
}

resource "aws_subnet" "app_private_a" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "192.168.0.0/24"
  availability_zone = local.az_a
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-private-subnet-a"
    "kubernetes.io/cluster/${local.name_prefix}-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb"                        = "1"
  })
}

resource "aws_subnet" "app_private_b" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "192.168.1.0/24"
  availability_zone = local.az_b
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-private-subnet-b"
    "kubernetes.io/cluster/${local.name_prefix}-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb"                        = "1"
  })
}

resource "aws_subnet" "app_data_a" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = local.az_a
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-app-data-subnet-a" })
}

resource "aws_subnet" "app_data_b" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "192.168.3.0/24"
  availability_zone = local.az_b
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-app-data-subnet-b" })
}

# ── Route Tables ─────────────────────────────────────────────────────────────

resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-hub-public-rtb" })
}

resource "aws_route" "hub_public_igw" {
  route_table_id         = aws_route_table.hub_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hub.id
}

resource "aws_route_table_association" "hub_public_a" {
  subnet_id      = aws_subnet.hub_public_a.id
  route_table_id = aws_route_table.hub_public.id
}

resource "aws_route_table_association" "hub_public_b" {
  subnet_id      = aws_subnet.hub_public_b.id
  route_table_id = aws_route_table.hub_public.id
}

resource "aws_route_table" "hub_firewall" {
  vpc_id = aws_vpc.hub.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-hub-firewall-rtb" })
}

resource "aws_route" "hub_firewall_nat" {
  route_table_id         = aws_route_table.hub_firewall.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.hub.id
}

resource "aws_route_table_association" "hub_firewall" {
  subnet_id      = aws_subnet.hub_firewall.id
  route_table_id = aws_route_table.hub_firewall.id
}

resource "aws_route_table" "hub_private_a" {
  vpc_id = aws_vpc.hub.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-hub-private-rtb-a" })
}

resource "aws_route_table" "hub_private_b" {
  vpc_id = aws_vpc.hub.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-hub-private-rtb-b" })
}

resource "aws_route_table_association" "hub_private_a" {
  subnet_id      = aws_subnet.hub_private_a.id
  route_table_id = aws_route_table.hub_private_a.id
}

resource "aws_route_table_association" "hub_private_b" {
  subnet_id      = aws_subnet.hub_private_b.id
  route_table_id = aws_route_table.hub_private_b.id
}

resource "aws_route_table" "app_private_a" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-app-private-rtb-a" })
}

resource "aws_route_table" "app_private_b" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-app-private-rtb-b" })
}

resource "aws_route_table_association" "app_private_a" {
  subnet_id      = aws_subnet.app_private_a.id
  route_table_id = aws_route_table.app_private_a.id
}

resource "aws_route_table_association" "app_private_b" {
  subnet_id      = aws_subnet.app_private_b.id
  route_table_id = aws_route_table.app_private_b.id
}

resource "aws_route_table" "app_data_a" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-app-data-rtb-a" })
}

resource "aws_route_table" "app_data_b" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-app-data-rtb-b" })
}

resource "aws_route_table_association" "app_data_a" {
  subnet_id      = aws_subnet.app_data_a.id
  route_table_id = aws_route_table.app_data_a.id
}

resource "aws_route_table_association" "app_data_b" {
  subnet_id      = aws_subnet.app_data_b.id
  route_table_id = aws_route_table.app_data_b.id
}

# ── Transit Gateway ──────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway" "main" {
  description                     = "gj2025 transit gateway"
  amazon_side_asn                 = 64512
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-tgw" })
}

resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = merge(local.common_tags, { Name = "${local.name_prefix}-hub-tgw-rtb" })
}

resource "aws_ec2_transit_gateway_route_table" "app" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = merge(local.common_tags, { Name = "${local.name_prefix}-app-tgw-rtb" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  subnet_ids                                      = [aws_subnet.hub_private_a.id, aws_subnet.hub_private_b.id]
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = aws_vpc.hub.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-hub-tgw-attach" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "app" {
  subnet_ids                                      = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]
  transit_gateway_id                              = aws_ec2_transit_gateway.main.id
  vpc_id                                          = aws_vpc.app.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-tgw-attach" })
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_association" "app" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.app.id
}

resource "aws_ec2_transit_gateway_route" "hub_to_app" {
  destination_cidr_block         = local.app_vpc_cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app.id
}

resource "aws_ec2_transit_gateway_route" "app_to_hub" {
  destination_cidr_block         = local.hub_vpc_cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.app.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_route" "app_to_internet_via_hub" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.app.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_route" "hub_private_a_tgw_app" {
  route_table_id         = aws_route_table.hub_private_a.id
  destination_cidr_block = local.app_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "hub_private_b_tgw_app" {
  route_table_id         = aws_route_table.hub_private_b.id
  destination_cidr_block = local.app_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "app_private_a_tgw" {
  route_table_id         = aws_route_table.app_private_a.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "app_private_b_tgw" {
  route_table_id         = aws_route_table.app_private_b.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "app_private_a_tgw_hub" {
  route_table_id         = aws_route_table.app_private_a.id
  destination_cidr_block = local.hub_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "app_private_b_tgw_hub" {
  route_table_id         = aws_route_table.app_private_b.id
  destination_cidr_block = local.hub_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "hub_public_app_via_tgw" {
  route_table_id         = aws_route_table.hub_public.id
  destination_cidr_block = local.app_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

# Hub NAT route for return traffic from app VPC internet egress
resource "aws_route" "hub_firewall_app_return" {
  route_table_id         = aws_route_table.hub_firewall.id
  destination_cidr_block = local.app_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
