resource "aws_kms_key" "rds" {
  description             = "RDS CMK encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-rds-kms" })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.app_data_a.id, aws_subnet.app_data_b.id]
  tags       = merge(local.common_tags, { Name = "${local.name_prefix}-db-subnet-group" })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL access from EKS and proxy"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "MySQL from EKS nodes"
    from_port       = 3309
    to_port         = 3309
    protocol        = "tcp"
    security_groups = [
      aws_security_group.eks_nodes.id,
      aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
    ]
  }

  ingress {
    description     = "MySQL from RDS Proxy"
    from_port       = 3309
    to_port         = 3309
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_proxy.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rds-sg" })
}

resource "aws_security_group" "rds_proxy" {
  name        = "${local.name_prefix}-rds-proxy-sg"
  description = "RDS Proxy access from EKS"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "Proxy from EKS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [
      aws_security_group.eks_nodes.id,
      aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rds-proxy-sg" })
}

resource "aws_db_parameter_group" "mysql" {
  name   = "${local.name_prefix}-mysql-pg"
  family = "mysql8.0"
  tags   = local.common_tags
}

resource "aws_db_instance" "main" {
  identifier                 = "${local.name_prefix}-db-instance"
  engine                     = "mysql"
  engine_version             = "8.0"
  instance_class             = "db.t3.medium"
  allocated_storage          = 20
  storage_type               = "gp3"
  db_name                    = "day1"
  username                   = "admin"
  password                   = var.db_password
  port                       = 3309
  db_subnet_group_name       = aws_db_subnet_group.main.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  parameter_group_name       = aws_db_parameter_group.mysql.name
  storage_encrypted          = true
  kms_key_id                 = aws_kms_key.rds.arn
  deletion_protection        = true
  skip_final_snapshot        = true
  publicly_accessible        = false
  multi_az                   = true
  backup_retention_period    = 1
  enabled_cloudwatch_logs_exports = ["general", "error", "audit"]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-instance" })
}

resource "aws_iam_role" "rds_proxy" {
  name = "${local.name_prefix}-rds-proxy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "rds_proxy" {
  name = "${local.name_prefix}-rds-proxy-policy"
  role = aws_iam_role.rds_proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db_credentials.arn
    }]
  })
}

resource "aws_db_proxy" "main" {
  name                   = "${local.name_prefix}-rds-proxy"
  engine_family          = "MYSQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  require_tls            = false

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rds-proxy" })
}

resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name
}

resource "aws_db_proxy_target" "main" {
  db_proxy_name         = aws_db_proxy.main.name
  target_group_name     = aws_db_proxy_default_target_group.main.name
  db_instance_identifier = aws_db_instance.main.identifier
}
