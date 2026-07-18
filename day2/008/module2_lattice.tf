############################################
# Module 2 — VPC Lattice (ap-northeast-1)
############################################

resource "aws_vpc" "lattice_client" {
  provider             = aws.tokyo
  cidr_block           = "10.61.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "skills-lattice-client-vpc" })
}

resource "aws_vpc" "lattice_service" {
  provider             = aws.tokyo
  cidr_block           = "10.62.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "skills-lattice-service-vpc" })
}

resource "aws_internet_gateway" "lattice_client" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.lattice_client.id
  tags     = merge(local.common_tags, { Name = "skills-lattice-client-igw" })
}

resource "aws_internet_gateway" "lattice_service" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.lattice_service.id
  tags     = merge(local.common_tags, { Name = "skills-lattice-service-igw" })
}

resource "aws_subnet" "lattice_client" {
  provider                = aws.tokyo
  vpc_id                  = aws_vpc.lattice_client.id
  cidr_block              = "10.61.1.0/24"
  availability_zone       = data.aws_availability_zones.tokyo.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "skills-lattice-client-subnet" })
}

resource "aws_subnet" "lattice_service_pub" {
  provider                = aws.tokyo
  vpc_id                  = aws_vpc.lattice_service.id
  cidr_block              = "10.62.1.0/24"
  availability_zone       = data.aws_availability_zones.tokyo.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "skills-lattice-service-pub" })
}

resource "aws_subnet" "lattice_service_priv" {
  provider          = aws.tokyo
  vpc_id            = aws_vpc.lattice_service.id
  cidr_block        = "10.62.11.0/24"
  availability_zone = data.aws_availability_zones.tokyo.names[0]
  tags              = merge(local.common_tags, { Name = "skills-lattice-service-priv" })
}

resource "aws_route_table" "lattice_client" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.lattice_client.id
  tags     = merge(local.common_tags, { Name = "skills-lattice-client-rt" })
}

resource "aws_route" "lattice_client_default" {
  provider               = aws.tokyo
  route_table_id         = aws_route_table.lattice_client.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lattice_client.id
}

resource "aws_route_table_association" "lattice_client" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.lattice_client.id
  route_table_id = aws_route_table.lattice_client.id
}

resource "aws_eip" "lattice_nat" {
  provider = aws.tokyo
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "skills-lattice-nat-eip" })
}

resource "aws_nat_gateway" "lattice_service" {
  provider      = aws.tokyo
  allocation_id = aws_eip.lattice_nat.id
  subnet_id     = aws_subnet.lattice_service_pub.id
  tags          = merge(local.common_tags, { Name = "skills-lattice-service-nat" })
  depends_on    = [aws_internet_gateway.lattice_service]
}

resource "aws_route_table" "lattice_service_pub" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.lattice_service.id
  tags     = merge(local.common_tags, { Name = "skills-lattice-service-pub-rt" })
}

resource "aws_route" "lattice_service_pub_default" {
  provider               = aws.tokyo
  route_table_id         = aws_route_table.lattice_service_pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lattice_service.id
}

resource "aws_route_table_association" "lattice_service_pub" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.lattice_service_pub.id
  route_table_id = aws_route_table.lattice_service_pub.id
}

resource "aws_route_table" "lattice_service_priv" {
  provider = aws.tokyo
  vpc_id   = aws_vpc.lattice_service.id
  tags     = merge(local.common_tags, { Name = "skills-lattice-service-priv-rt" })
}

resource "aws_route" "lattice_service_priv_default" {
  provider               = aws.tokyo
  route_table_id         = aws_route_table.lattice_service_priv.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.lattice_service.id
}

resource "aws_route_table_association" "lattice_service_priv" {
  provider       = aws.tokyo
  subnet_id      = aws_subnet.lattice_service_priv.id
  route_table_id = aws_route_table.lattice_service_priv.id
}

resource "aws_security_group" "lattice_client" {
  provider    = aws.tokyo
  name        = "skills-lattice-client-sg"
  description = "client"
  vpc_id      = aws_vpc.lattice_client.id
  tags        = merge(local.common_tags, { Name = "skills-lattice-client-sg" })

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
}

resource "aws_security_group" "lattice_service" {
  provider    = aws.tokyo
  name        = "skills-lattice-service-sg"
  description = "service"
  vpc_id      = aws_vpc.lattice_service.id
  tags        = merge(local.common_tags, { Name = "skills-lattice-service-sg" })

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice_tokyo.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lattice_sn_assoc" {
  provider    = aws.tokyo
  name        = "skills-lattice-sn-assoc-sg"
  description = "SN assoc"
  vpc_id      = aws_vpc.lattice_client.id
  tags        = merge(local.common_tags, { Name = "skills-lattice-sn-assoc-sg" })

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.61.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "lattice_ec2" {
  name = "skills-lattice-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lattice_ssm" {
  role       = aws_iam_role.lattice_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "lattice_s3" {
  name = "s3read"
  role = aws_iam_role.lattice_ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.lattice_deploy.arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "lattice_ec2" {
  name = "skills-lattice-ec2-profile"
  role = aws_iam_role.lattice_ec2.name
}

resource "aws_s3_bucket" "lattice_deploy" {
  provider = aws.tokyo
  bucket   = "skills-lattice-deploy-${local.account_id}-an1"
  tags     = local.common_tags
}

resource "aws_s3_object" "client_app" {
  provider = aws.tokyo
  bucket   = aws_s3_bucket.lattice_deploy.id
  key      = "client_app.py"
  source   = "${path.module}/모듈2_지급파일/client_app.py"
  etag     = filemd5("${path.module}/모듈2_지급파일/client_app.py")
}

resource "aws_s3_object" "service_app" {
  provider = aws.tokyo
  bucket   = aws_s3_bucket.lattice_deploy.id
  key      = "service_app.py"
  source   = "${path.module}/모듈2_지급파일/service_app.py"
  etag     = filemd5("${path.module}/모듈2_지급파일/service_app.py")
}

resource "aws_instance" "lattice_service" {
  provider                    = aws.tokyo
  ami                         = local.ami_tokyo
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.lattice_service_priv.id
  vpc_security_group_ids      = [aws_security_group.lattice_service.id]
  iam_instance_profile        = aws_iam_instance_profile.lattice_ec2.name
  associate_public_ip_address = false
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/files/lattice_service_userdata.sh.tftpl", {
    bucket = aws_s3_bucket.lattice_deploy.id
    region = "ap-northeast-1"
  })

  depends_on = [aws_nat_gateway.lattice_service, aws_s3_object.service_app]
  tags       = merge(local.common_tags, { Name = "skills-lattice-service-ec2" })
}

resource "aws_vpclattice_service_network" "main" {
  provider = aws.tokyo
  name     = "skills-lattice-sn"
  tags     = merge(local.common_tags, { Name = "skills-lattice-sn" })
}

resource "aws_vpclattice_service_network_vpc_association" "client" {
  provider                     = aws.tokyo
  vpc_identifier               = aws_vpc.lattice_client.id
  service_network_identifier   = aws_vpclattice_service_network.main.id
  security_group_ids           = [aws_security_group.lattice_sn_assoc.id]
}

resource "aws_vpclattice_target_group" "order" {
  provider = aws.tokyo
  name     = "skills-lattice-order-tg"
  type     = "INSTANCE"
  config {
    port           = 8080
    protocol       = "HTTP"
    vpc_identifier = aws_vpc.lattice_service.id
    health_check {
      enabled  = true
      protocol = "HTTP"
      path     = "/health"
      port     = 8080
    }
  }
  tags = merge(local.common_tags, { Name = "skills-lattice-order-tg" })
}

resource "aws_vpclattice_target_group_attachment" "service" {
  provider           = aws.tokyo
  target_group_identifier = aws_vpclattice_target_group.order.id
  target {
    id   = aws_instance.lattice_service.id
    port = 8080
  }
}

resource "aws_vpclattice_service" "order" {
  provider = aws.tokyo
  name     = "skills-lattice-order-service"
  tags     = merge(local.common_tags, { Name = "skills-lattice-order-service" })
}

resource "aws_vpclattice_service_network_service_association" "order" {
  provider                   = aws.tokyo
  service_identifier         = aws_vpclattice_service.order.id
  service_network_identifier = aws_vpclattice_service_network.main.id
}

resource "aws_vpclattice_listener" "http" {
  provider           = aws.tokyo
  name               = "skills-lattice-http-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.order.id
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order.id
      }
    }
  }
  tags = merge(local.common_tags, { Name = "skills-lattice-http-listener" })
}

resource "aws_instance" "lattice_client" {
  provider                    = aws.tokyo
  ami                         = local.ami_tokyo
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.lattice_client.id
  vpc_security_group_ids      = [aws_security_group.lattice_client.id]
  iam_instance_profile        = aws_iam_instance_profile.lattice_ec2.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/files/lattice_client_userdata.sh.tftpl", {
    bucket      = aws_s3_bucket.lattice_deploy.id
    region      = "ap-northeast-1"
    service_url = "http://${aws_vpclattice_service.order.dns_entry[0].domain_name}"
  })

  depends_on = [
    aws_vpclattice_listener.http,
    aws_vpclattice_service_network_service_association.order,
    aws_vpclattice_service_network_vpc_association.client,
    aws_s3_object.client_app,
  ]

  tags = merge(local.common_tags, { Name = "skills-lattice-client-ec2" })
}
