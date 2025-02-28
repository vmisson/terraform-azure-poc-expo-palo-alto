output "firewall-name" {
  value = azurerm_public_ip.management.domain_name_label
}

output "password" {
  value     = random_password.this.result
  sensitive = true
}