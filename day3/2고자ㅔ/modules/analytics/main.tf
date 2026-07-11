terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    null = {
      source = "hashicorp/null"
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  app_py         = file("${path.module}/../../Real-time data analytics/app.py")
  stream_proc_py = file("${path.module}/stream_proc.py")
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_key_pair" "data" {
  key_name   = "gj2026-data-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "data" {
  name        = "gj2026-data-sg"
  description = "GJ2026 data analytics"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = { Name = "gj2026-data-sg" }
}

resource "aws_iam_role" "data_ec2" {
  name = "gj2026-data-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "data_ec2_ssm" {
  role       = aws_iam_role.data_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "data_ec2_elb" {
  name = "gj2026-data-ec2-elb"
  role = aws_iam_role.data_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["elasticloadbalancing:DescribeLoadBalancers"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "data_ec2" {
  name = "gj2026-data-ec2-profile"
  role = aws_iam_role.data_ec2.name
}

resource "aws_instance" "data" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.data.id]
  iam_instance_profile        = aws_iam_instance_profile.data_ec2.name
  key_name                    = aws_key_pair.data.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = false

  user_data_base64 = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    app_py_b64      = base64encode(local.app_py)
    nlb_dns         = "kafka-bootstrap.local"
    stream_proc_b64 = base64encode(local.stream_proc_py)
  }))

  tags = { Name = "gj2026-data-ec2" }
}

resource "aws_lb" "kafka" {
  name               = "gj2026-data-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = data.aws_subnets.default.ids

  tags = { Name = "gj2026-data-nlb" }
}

resource "aws_lb_target_group" "kafka" {
  name        = "gj2026-data-kafka-tg"
  port        = 9094
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "9094"
  }
}

resource "aws_lb_target_group_attachment" "kafka" {
  target_group_arn = aws_lb_target_group.kafka.arn
  target_id        = aws_instance.data.id
  port             = 9094
}

resource "aws_lb_listener" "kafka" {
  load_balancer_arn = aws_lb.kafka.arn
  port              = 9094
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka.arn
  }
}

resource "null_resource" "kafka_external" {
  triggers = {
    nlb_dns     = aws_lb.kafka.dns_name
    instance_id = aws_instance.data.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      source /root/projects/korean_skills_2026/build/load-env.sh
      load_repo_env /root/projects/korean_skills_2026/build
      NLB="${aws_lb.kafka.dns_name}"
      IID="${aws_instance.data.id}"
      for i in $(seq 1 90); do
        STATUS=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$IID" --region ap-southeast-1 --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "")
        [ "$STATUS" = "Online" ] && break
        sleep 10
      done
      CMD=$(aws ssm send-command --region ap-southeast-1 --instance-ids "$IID" \
        --document-name AWS-RunShellScript \
        --parameters "commands=[\"sed -i 's|advertised.listeners=.*|advertised.listeners=PLAINTEXT://127.0.0.1:9092,EXTERNAL://$NLB:9094|' /opt/kafka/config/kraft/server.properties\",\"systemctl restart kafka\"]" \
        --query Command.CommandId --output text)
      aws ssm wait command-executed --region ap-southeast-1 --command-id "$CMD" --instance-id "$IID" || true
    EOT
  }

  depends_on = [aws_lb_listener.kafka, aws_instance.data]
}

resource "null_resource" "stream_proc" {
  triggers = {
    instance_id = aws_instance.data.id
    script_hash = filemd5("${path.module}/stream_proc.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      source /root/projects/korean_skills_2026/build/load-env.sh
      load_repo_env /root/projects/korean_skills_2026/build
      KEY=/tmp/gj2026-analytics.pem
      IP="${aws_instance.data.public_ip}"
      cd /root/projects/korean_skills_2026/day3/2고자ㅔ
      ../../terraform output -raw ssh_private_key_pem > "$KEY"
      chmod 600 "$KEY"
      scp -o StrictHostKeyChecking=no -i "$KEY" ${path.module}/stream_proc.py ec2-user@$IP:/tmp/stream_proc.py
      ssh -o StrictHostKeyChecking=no -i "$KEY" ec2-user@$IP 'sudo cp /tmp/stream_proc.py /home/ec2-user/stream_proc.py && sudo chown ec2-user:ec2-user /home/ec2-user/stream_proc.py && sudo chmod +x /home/ec2-user/stream_proc.py && sudo tee /etc/systemd/system/gj2026-stream-proc.service > /dev/null <<'"'"'UNIT'"'"'
[Unit]
Description=GJ2026 Kafka stream processor
After=kafka.service
Requires=kafka.service
[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/stream_proc.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable gj2026-stream-proc && sudo systemctl restart gj2026-stream-proc'
    EOT
  }

  depends_on = [null_resource.kafka_external]
}

resource "aws_glue_catalog_database" "analytics" {
  name = "real_time_analytics"
}

resource "aws_iam_role" "flink" {
  name = "gj2026-data-flink-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kinesisanalytics.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flink" {
  name = "gj2026-data-flink-policy"
  role = aws_iam_role.flink.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:*", "glue:*", "s3:GetObject", "s3:GetObjectVersion"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "flink" {
  name        = "gj2026-data-flink-sg"
  description = "Managed Flink to Kafka NLB"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj2026-data-flink-sg" }
}

resource "null_resource" "flink_app" {
  triggers = {
    bootstrap = "${aws_lb.kafka.dns_name}:9094"
    glue_arn  = aws_glue_catalog_database.analytics.arn
    role_arn  = aws_iam_role.flink.arn
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      source /root/projects/korean_skills_2026/build/load-env.sh
      load_repo_env /root/projects/korean_skills_2026/build
      REGION=ap-southeast-1
      APP=gj2026-data-flink
      ROLE="${aws_iam_role.flink.arn}"
      GLUE="${aws_glue_catalog_database.analytics.arn}"
      VPC="${data.aws_vpc.default.id}"
      SUBNET="${data.aws_subnets.default.ids[0]}"
      FLINK_SG="${aws_security_group.flink.id}"
      if aws kinesisanalyticsv2 describe-application --region "$REGION" --application-name "$APP" >/dev/null 2>&1; then
        echo "Flink app exists"
      else
        aws kinesisanalyticsv2 create-application --region "$REGION" \
          --application-name "$APP" \
          --runtime-environment ZEPPELIN-FLINK-3_0 \
          --application-mode INTERACTIVE \
          --service-execution-role "$ROLE" \
          --application-configuration "{
            \"ZeppelinApplicationConfiguration\": {
              \"CatalogConfiguration\": {
                \"GlueDataCatalogConfiguration\": {
                  \"DatabaseARN\": \"$GLUE\"
                }
              }
            },
            \"FlinkApplicationConfiguration\": {
              \"ParallelismConfiguration\": {
                \"ConfigurationType\": \"CUSTOM\",
                \"Parallelism\": 2,
                \"ParallelismPerKPU\": 1,
                \"AutoScalingEnabled\": false
              }
            }
          }" || exit 1
      fi
      aws kinesisanalyticsv2 start-application --region "$REGION" \
        --application-name "$APP" 2>/dev/null || true
    EOT
  }

  depends_on = [null_resource.kafka_external, aws_glue_catalog_database.analytics, aws_iam_role_policy.flink]
}

resource "null_resource" "flink_sql" {
  triggers = {
    nlb_dns  = aws_lb.kafka.dns_name
    sql_hash = filemd5("${path.module}/flink.sql.tpl")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "chmod +x ${path.module}/deploy_flink.sh && ${path.module}/deploy_flink.sh ap-southeast-1 gj2026-data-flink ${aws_lb.kafka.dns_name}"
  }

  depends_on = [null_resource.flink_app]
}
