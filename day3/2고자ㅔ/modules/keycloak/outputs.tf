output "keycloak_public_ip" {
  value = aws_instance.keycloak.public_ip
}

output "keycloak_url" {
  value = "https://${aws_instance.keycloak.public_ip}"
}

output "keycloak_hostname" {
  value = "${replace(aws_instance.keycloak.public_ip, ".", "-")}.sslip.io"
}
