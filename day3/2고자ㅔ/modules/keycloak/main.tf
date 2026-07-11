terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

locals {
  keycloak_host = "${replace(aws_instance.keycloak.public_ip, ".", "-")}.sslip.io"
}

resource "aws_vpc" "keycloak" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "gj2026-keycloak-vpc" }
}

resource "aws_internet_gateway" "keycloak" {
  vpc_id = aws_vpc.keycloak.id

  tags = { Name = "gj2026-keycloak-igw" }
}

resource "aws_subnet" "keycloak" {
  vpc_id                  = aws_vpc.keycloak.id
  cidr_block              = "10.30.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = { Name = "gj2026-keycloak-subnet" }
}

resource "aws_route_table" "keycloak" {
  vpc_id = aws_vpc.keycloak.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.keycloak.id
  }

  tags = { Name = "gj2026-keycloak-rt" }
}

resource "aws_route_table_association" "keycloak" {
  subnet_id      = aws_subnet.keycloak.id
  route_table_id = aws_route_table.keycloak.id
}

resource "aws_key_pair" "keycloak" {
  key_name   = "gj2026-keycloak-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "keycloak" {
  name        = "gj2026-keycloak-sg"
  description = "Keycloak HTTPS and SSH"
  vpc_id      = aws_vpc.keycloak.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

  tags = { Name = "gj2026-keycloak-sg" }
}

resource "aws_iam_role" "keycloak_ec2" {
  name = "gj2026-keycloak-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "keycloak_ec2" {
  name = "gj2026-keycloak-ec2-policy"
  role = aws_iam_role.keycloak_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRoleWithWebIdentity",
          "iam:ListRoles",
          "iam:ListOpenIDConnectProviders",
          "iam:GetRole",
          "iam:ListAttachedRolePolicies",
          "iam:UpdateOpenIDConnectProviderThumbprint"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "keycloak_ssm" {
  role       = aws_iam_role.keycloak_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "keycloak_ec2" {
  name = "gj2026-keycloak-ec2-profile"
  role = aws_iam_role.keycloak_ec2.name
}

resource "aws_instance" "keycloak" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.keycloak.id
  vpc_security_group_ids      = [aws_security_group.keycloak.id]
  iam_instance_profile        = aws_iam_instance_profile.keycloak_ec2.name
  key_name                    = aws_key_pair.keycloak.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data_base64 = base64encode(file("${path.module}/userdata.sh.tpl"))

  tags = { Name = "gj2026-keycloak-ec2" }
}

# Team EC2는 채점 스크립트(keycloak.sh 4-0)가 생성하므로 Terraform에서 관리하지 않음

resource "aws_iam_openid_connect_provider" "keycloak" {
  url             = "https://${local.keycloak_host}/realms/team"
  client_id_list  = ["gj2026-keycloak-dev", "gj2026-keycloak-sec", "sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  lifecycle {
    ignore_changes = [thumbprint_list]
  }

  depends_on = [aws_instance.keycloak]
}

resource "aws_iam_role" "dev" {
  name = "gj2026-keycloak-dev-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.keycloak.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.keycloak.url, "https://", "")}:aud" = "gj2026-keycloak-dev"
        }
      }
    }]
  })
}

resource "aws_iam_role" "sec" {
  name = "gj2026-keycloak-sec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.keycloak.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.keycloak.url, "https://", "")}:aud" = "gj2026-keycloak-sec"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "dev" {
  name = "gj2026-keycloak-dev-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = "arn:aws:ec2:eu-central-1:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/team" = "dev-team"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "sec" {
  name = "gj2026-keycloak-sec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = "arn:aws:ec2:eu-central-1:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/team" = "sec-team"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dev" {
  role       = aws_iam_role.dev.name
  policy_arn = aws_iam_policy.dev.arn
}

resource "aws_iam_role_policy_attachment" "sec" {
  role       = aws_iam_role.sec.name
  policy_arn = aws_iam_policy.sec.arn
}

# Keycloak 기동 후 OIDC thumbprint 갱신 + 채점용 로컬 AWS 프로필 설치
resource "null_resource" "oidc_and_profiles" {
  triggers = {
    instance_id = aws_instance.keycloak.id
    public_ip   = aws_instance.keycloak.public_ip
    provider    = aws_iam_openid_connect_provider.keycloak.arn
  }

  depends_on = [
    aws_instance.keycloak,
    aws_iam_openid_connect_provider.keycloak,
    aws_iam_role_policy_attachment.dev,
    aws_iam_role_policy_attachment.sec,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      HOST="${local.keycloak_host}"
      ARN="${aws_iam_openid_connect_provider.keycloak.arn}"
      CREDS_SRC="${path.module}/gj2026-keycloak-creds.sh"
      CREDS_DST="$HOME/.aws/gj2026-keycloak-creds.sh"

      echo "Waiting for Keycloak realm at https://$HOST/realms/team ..."
      for i in $(seq 1 90); do
        if curl -sk "https://$HOST/realms/team" | grep -q '"realm"'; then
          echo "realm ready ($i)"
          break
        fi
        # also accept IP access used by scoring script
        IP="${aws_instance.keycloak.public_ip}"
        if curl -sk "https://$IP/realms/team" | grep -q '"realm"'; then
          echo "realm ready via IP ($i)"
          break
        fi
        sleep 10
      done

      THUMB=$(openssl s_client -connect "$HOST:443" -servername "$HOST" </dev/null 2>/dev/null \
        | openssl x509 -fingerprint -sha1 -noout \
        | awk -F= '{print tolower($2)}' | tr -d ':')
      if [ "$${#THUMB}" -ne 40 ]; then
        THUMB=$(openssl s_client -connect "${aws_instance.keycloak.public_ip}:443" -servername "$HOST" </dev/null 2>/dev/null \
          | openssl x509 -fingerprint -sha1 -noout \
          | awk -F= '{print tolower($2)}' | tr -d ':')
      fi
      echo "thumbprint=$THUMB"
      test "$${#THUMB}" -eq 40
      aws iam update-open-id-connect-provider-thumbprint \
        --open-id-connect-provider-arn "$ARN" \
        --thumbprint-list "$THUMB"

      mkdir -p "$HOME/.aws"
      cp "$CREDS_SRC" "$CREDS_DST"
      chmod +x "$CREDS_DST"
      aws configure set credential_process "$CREDS_DST dev dev-user" --profile gj2026-keycloak-dev
      aws configure set region eu-central-1 --profile gj2026-keycloak-dev
      aws configure set credential_process "$CREDS_DST sec sec-user" --profile gj2026-keycloak-sec
      aws configure set region eu-central-1 --profile gj2026-keycloak-sec
      echo "local AWS profiles configured"
    EOT
  }
}
