# Output the Public IP of the VM
output "public_ip" {
  value       = azurerm_public_ip.private_vm_public_ip.ip_address
  description = "The public IP address of the virtual machine"
}
