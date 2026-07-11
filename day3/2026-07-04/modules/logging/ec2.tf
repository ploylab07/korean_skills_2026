resource "tls_private_key" "app" {
  count     = var.bastion_key_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "app" {
  count      = var.bastion_key_name == "" ? 1 : 0
  key_name   = "wsc-logging-app-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.app[0].public_key_openssh
}

locals {
  app_key_name = var.bastion_key_name != "" ? var.bastion_key_name : aws_key_pair.app[0].key_name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.pub_a.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  key_name                    = local.app_key_name
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/app-userdata.sh", {
    app_py           = file("${path.module}/../../app.py")
    requirements_txt = file("${path.module}/../../requirements.txt")
    dockerfile       = file("${path.module}/../../Dockerfile")
    loki_host        = try(data.kubernetes_service.loki.status[0].load_balancer[0].ingress[0].hostname, "loki-pending")
  }))

  tags = merge(local.tags, { Name = "wsc-log-app-bastion" })

  depends_on = [helm_release.loki]
}
