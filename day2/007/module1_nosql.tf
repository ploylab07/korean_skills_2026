############################################
# Module 1 — NoSQL (ap-southeast-1 / singapore)
############################################

resource "aws_dynamodb_table" "reservation" {
  provider     = aws.singapore
  name         = "bigbae-nosql-reservation-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "train_id"
  range_key    = "seat_id"

  attribute {
    name = "train_id"
    type = "S"
  }

  attribute {
    name = "seat_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "reserved_at"
    type = "S"
  }

  global_secondary_index {
    name            = "gsi-user-reservations"
    hash_key        = "user_id"
    range_key       = "reserved_at"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table" "audit" {
  provider     = aws.singapore
  name         = "bigbae-nosql-audit-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = local.common_tags
}

############################################
# Lambda — reservation stream audit
############################################

data "archive_file" "reservation_audit_lambda" {
  type        = "zip"
  source_file = "${path.module}/Module1-NoSQL/lambda.py"
  output_path = "${path.module}/.generated/reservation-audit-lambda.zip"
}

resource "aws_iam_role" "reservation_audit_lambda" {
  provider = aws.singapore
  name     = "bigbae-nosql-reservation-audit-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "reservation_audit_lambda_basic" {
  provider   = aws.singapore
  role       = aws_iam_role.reservation_audit_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "reservation_audit_lambda" {
  provider = aws.singapore
  name     = "bigbae-nosql-reservation-audit-policy"
  role     = aws_iam_role.reservation_audit_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [aws_dynamodb_table.audit.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams",
        ]
        Resource = [aws_dynamodb_table.reservation.stream_arn]
      },
    ]
  })
}

resource "aws_lambda_function" "reservation_audit" {
  provider         = aws.singapore
  function_name    = "bigbae-nosql-reservation-audit"
  role             = aws_iam_role.reservation_audit_lambda.arn
  handler          = "lambda.handler"
  runtime          = "python3.13"
  timeout          = 30
  filename         = data.archive_file.reservation_audit_lambda.output_path
  source_code_hash = data.archive_file.reservation_audit_lambda.output_base64sha256

  environment {
    variables = {
      AUDIT_TABLE_NAME = aws_dynamodb_table.audit.name
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "reservation_stream" {
  provider          = aws.singapore
  event_source_arn  = aws_dynamodb_table.reservation.stream_arn
  function_name     = aws_lambda_function.reservation_audit.arn
  starting_position = "LATEST"

  depends_on = [aws_iam_role_policy.reservation_audit_lambda]
}

############################################
# EC2 — Flask app
############################################

data "aws_vpc" "default_singapore" {
  provider = aws.singapore
  default  = true
}

data "aws_subnets" "default_singapore" {
  provider = aws.singapore
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_singapore.id]
  }
}

data "aws_ami" "al2023_singapore" {
  provider    = aws.singapore
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "nosql_app" {
  provider    = aws.singapore
  name        = "bigbae-nosql-app-sg"
  description = "Allow app traffic for bigbae-nosql-app-ec2"
  vpc_id      = data.aws_vpc.default_singapore.id

  ingress {
    description = "app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_iam_role" "nosql_app_ec2" {
  provider = aws.singapore
  name     = "bigbae-nosql-app-ec2-role"

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

resource "aws_iam_role_policy" "nosql_app_ec2" {
  provider = aws.singapore
  name     = "bigbae-nosql-app-ec2-policy"
  role     = aws_iam_role.nosql_app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      Resource = [
        aws_dynamodb_table.reservation.arn,
        "${aws_dynamodb_table.reservation.arn}/index/*",
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "nosql_app_ec2" {
  provider = aws.singapore
  name     = "bigbae-nosql-app-ec2-profile"
  role     = aws_iam_role.nosql_app_ec2.name
}

resource "aws_instance" "nosql_app" {
  provider                   = aws.singapore
  ami                        = data.aws_ami.al2023_singapore.id
  instance_type               = "t3.small"
  subnet_id                   = data.aws_subnets.default_singapore.ids[0]
  vpc_security_group_ids      = [aws_security_group.nosql_app.id]
  iam_instance_profile        = aws_iam_instance_profile.nosql_app_ec2.name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf install -y python3 python3-pip
    mkdir -p /opt/app
    cat > /opt/app/requirements.txt <<'REQS'
    ${file("${path.module}/Module1-NoSQL/requirements.txt")}
    REQS
    cat > /opt/app/app.py <<'APPPY'
    ${file("${path.module}/Module1-NoSQL/app.py")}
    APPPY
    pip3 install -r /opt/app/requirements.txt
    cat > /etc/systemd/system/nosql-app.service <<'UNIT'
    [Unit]
    Description=bigbae nosql app
    After=network.target

    [Service]
    Environment=AWS_REGION=ap-southeast-1
    Environment=TABLE_NAME=${aws_dynamodb_table.reservation.name}
    Environment=GSI_NAME=gsi-user-reservations
    ExecStart=/usr/bin/python3 /opt/app/app.py
    Restart=always
    User=root

    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now nosql-app.service
  EOF

  tags = merge(local.common_tags, {
    Name = "bigbae-nosql-app-ec2"
  })
}
