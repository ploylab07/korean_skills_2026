resource "tls_private_key" "bastion" {
  count     = var.bastion_key_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  count      = var.bastion_key_name == "" ? 1 : 0
  key_name   = "wsc-hub-bastion-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.bastion[0].public_key_openssh
}

locals {
  key_name = var.bastion_key_name != "" ? var.bastion_key_name : aws_key_pair.bastion[0].key_name
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_eip" "hub_bastion" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "wsc-hub-bastion-eip" })
}

resource "aws_instance" "hub_bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.hub_pub_a.id
  vpc_security_group_ids      = [aws_security_group.hub_bastion.id]
  key_name                    = local.key_name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euxo pipefail
    echo "root:${var.bastion_password}" | chpasswd
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    dnf install -y python3.12 python3.12-pip
  EOF
  )

  tags = merge(local.tags, { Name = "wsc-hub-bastion" })
}

resource "aws_eip_association" "hub_bastion" {
  instance_id   = aws_instance.hub_bastion.id
  allocation_id = aws_eip.hub_bastion.id
}

locals {
  app_user_data_v1 = base64encode(<<-SCRIPT
#!/bin/bash
set -euxo pipefail
dnf install -y python3.12 python3.12-pip
mkdir -p /opt/app
cat > /opt/app/version1.py <<'PYEOF'
${file("${path.module}/../../version1.py")}
PYEOF
pip3.12 install flask==3.1.3
nohup python3.12 /opt/app/version1.py > /var/log/app.log 2>&1 &
SCRIPT
  )

  app_user_data_v2 = base64encode(<<-SCRIPT
#!/bin/bash
set -euxo pipefail
dnf install -y python3.12 python3.12-pip
mkdir -p /opt/app
cat > /opt/app/version2.py <<'PYEOF'
${file("${path.module}/../../version2.py")}
PYEOF
pip3.12 install flask==3.1.3
nohup python3.12 /opt/app/version2.py > /var/log/app.log 2>&1 &
SCRIPT
  )
}

resource "aws_instance" "app_v1" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.spoke_priv_a.id
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.app_user_data_v1

  tags = merge(local.tags, { Name = "wsc-spoke-app-v1" })
}

resource "aws_instance" "app_v2" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.spoke_priv_a.id
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.app_user_data_v2

  tags = merge(local.tags, { Name = "wsc-spoke-app-v2" })
}
