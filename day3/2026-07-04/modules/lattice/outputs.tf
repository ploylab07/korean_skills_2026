output "bastion_public_ip" {
  value = aws_eip.hub_bastion.public_ip
}

output "lattice_dns" {
  value = aws_vpclattice_service.main.dns_entry[0].domain_name
}
