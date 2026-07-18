############################################
# Module 1 — DocumentDB NoSQL (ap-northeast-2)
############################################

resource "random_password" "docdb" {
  length           = 20
  special          = false
  override_special = ""
}

resource "aws_kms_key" "docdb" {
  provider                = aws.seoul
  description             = "skills-nosql-docdb"
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_kms_alias" "docdb" {
  provider      = aws.seoul
  name          = "alias/skills-nosql-docdb"
  target_key_id = aws_kms_key.docdb.key_id
}

resource "aws_vpc" "nosql" {
  provider             = aws.seoul
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "skills-nosql-vpc" })
}

resource "aws_internet_gateway" "nosql" {
  provider = aws.seoul
  vpc_id   = aws_vpc.nosql.id
  tags     = merge(local.common_tags, { Name = "skills-nosql-igw" })
}

resource "aws_subnet" "nosql_public" {
  provider                = aws.seoul
  vpc_id                  = aws_vpc.nosql.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.seoul.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "skills-nosql-public-subnet" })
}

resource "aws_subnet" "nosql_private_a" {
  provider          = aws.seoul
  vpc_id            = aws_vpc.nosql.id
  cidr_block        = "10.50.11.0/24"
  availability_zone = data.aws_availability_zones.seoul.names[0]
  tags              = merge(local.common_tags, { Name = "skills-nosql-private-subnet-a" })
}

resource "aws_subnet" "nosql_private_b" {
  provider          = aws.seoul
  vpc_id            = aws_vpc.nosql.id
  cidr_block        = "10.50.12.0/24"
  availability_zone = data.aws_availability_zones.seoul.names[1]
  tags              = merge(local.common_tags, { Name = "skills-nosql-private-subnet-b" })
}

resource "aws_route_table" "nosql_public" {
  provider = aws.seoul
  vpc_id   = aws_vpc.nosql.id
  tags     = merge(local.common_tags, { Name = "skills-nosql-public-rt" })
}

resource "aws_route" "nosql_public_default" {
  provider               = aws.seoul
  route_table_id         = aws_route_table.nosql_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.nosql.id
}

resource "aws_route_table_association" "nosql_public" {
  provider       = aws.seoul
  subnet_id      = aws_subnet.nosql_public.id
  route_table_id = aws_route_table.nosql_public.id
}

resource "aws_route_table" "nosql_private" {
  provider = aws.seoul
  vpc_id   = aws_vpc.nosql.id
  tags     = merge(local.common_tags, { Name = "skills-nosql-private-rt" })
}

resource "aws_route_table_association" "nosql_private_a" {
  provider       = aws.seoul
  subnet_id      = aws_subnet.nosql_private_a.id
  route_table_id = aws_route_table.nosql_private.id
}

resource "aws_route_table_association" "nosql_private_b" {
  provider       = aws.seoul
  subnet_id      = aws_subnet.nosql_private_b.id
  route_table_id = aws_route_table.nosql_private.id
}

resource "aws_security_group" "nosql_client" {
  provider    = aws.seoul
  name        = "skills-nosql-client-sg"
  description = "Client EC2 SG"
  vpc_id      = aws_vpc.nosql.id
  tags        = merge(local.common_tags, { Name = "skills-nosql-client-sg" })

  ingress {
    from_port   = 8080
    to_port     = 8080
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

resource "aws_security_group" "nosql_docdb" {
  provider    = aws.seoul
  name        = "skills-nosql-docdb-sg"
  description = "DocDB SG"
  vpc_id      = aws_vpc.nosql.id
  tags        = merge(local.common_tags, { Name = "skills-nosql-docdb-sg" })

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.nosql_client.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_docdb_subnet_group" "nosql" {
  provider   = aws.seoul
  name       = "skills-nosql-subnet-group"
  subnet_ids = [aws_subnet.nosql_private_a.id, aws_subnet.nosql_private_b.id]
  tags       = local.common_tags
}

resource "aws_docdb_cluster" "nosql" {
  provider                  = aws.seoul
  cluster_identifier        = "skills-nosql-docdb-cluster"
  engine                    = "docdb"
  master_username           = "skillsadmin"
  master_password           = random_password.docdb.result
  db_subnet_group_name      = aws_docdb_subnet_group.nosql.name
  vpc_security_group_ids    = [aws_security_group.nosql_docdb.id]
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.docdb.arn
  backup_retention_period   = 1
  skip_final_snapshot       = true
  deletion_protection       = false
  tags                      = local.common_tags
}

resource "aws_docdb_cluster_instance" "nosql_1" {
  provider           = aws.seoul
  identifier         = "skills-nosql-docdb-instance-1"
  cluster_identifier = aws_docdb_cluster.nosql.id
  instance_class     = "db.t3.medium"
  engine             = "docdb"
  tags               = local.common_tags
}

resource "aws_secretsmanager_secret" "nosql" {
  provider                = aws.seoul
  name                    = "skills-nosql-docdb-secret"
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "nosql" {
  provider  = aws.seoul
  secret_id = aws_secretsmanager_secret.nosql.id
  secret_string = jsonencode({
    username = "skillsadmin"
    password = random_password.docdb.result
    host     = aws_docdb_cluster.nosql.endpoint
  })
}

resource "aws_s3_bucket" "nosql_deploy" {
  provider = aws.seoul
  bucket   = "skills-nosql-deploy-${local.account_id}-an2"
  tags     = local.common_tags
}

resource "aws_s3_object" "docdb_client" {
  provider = aws.seoul
  bucket   = aws_s3_bucket.nosql_deploy.id
  key      = "docdb_client.py"
  source   = "${path.module}/모듈1_지급파일/docdb_client.py"
  etag     = filemd5("${path.module}/모듈1_지급파일/docdb_client.py")
}

resource "aws_s3_object" "retail_dataset" {
  provider = aws.seoul
  bucket   = aws_s3_bucket.nosql_deploy.id
  key      = "retail_dataset.json"
  source   = "${path.module}/모듈1_지급파일/retail_dataset.json"
  etag     = filemd5("${path.module}/모듈1_지급파일/retail_dataset.json")
}

resource "aws_s3_object" "create_indexes" {
  provider = aws.seoul
  bucket   = aws_s3_bucket.nosql_deploy.id
  key      = "create_indexes.py"
  content  = file("${path.module}/files/create_indexes.py")
  etag     = filemd5("${path.module}/files/create_indexes.py")
}

resource "aws_iam_role" "nosql_ec2" {
  name = "skills-nosql-ec2-role"
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

resource "aws_iam_role_policy_attachment" "nosql_ssm" {
  role       = aws_iam_role.nosql_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "nosql_ec2" {
  name = "skills-nosql-ec2-inline"
  role = aws_iam_role.nosql_ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.nosql.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.nosql_deploy.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nosql_ec2" {
  name = "skills-nosql-ec2-profile"
  role = aws_iam_role.nosql_ec2.name
}

resource "aws_instance" "nosql_client" {
  provider                    = aws.seoul
  ami                         = local.ami_seoul
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.nosql_public.id
  vpc_security_group_ids      = [aws_security_group.nosql_client.id]
  iam_instance_profile        = aws_iam_instance_profile.nosql_ec2.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/files/nosql_userdata.sh.tftpl", {
    bucket = aws_s3_bucket.nosql_deploy.id
    region = "ap-northeast-2"
  })

  depends_on = [
    aws_docdb_cluster_instance.nosql_1,
    aws_secretsmanager_secret_version.nosql,
    aws_s3_object.docdb_client,
    aws_s3_object.retail_dataset,
    aws_s3_object.create_indexes,
  ]

  tags = merge(local.common_tags, { Name = "skills-nosql-client-ec2" })
}
