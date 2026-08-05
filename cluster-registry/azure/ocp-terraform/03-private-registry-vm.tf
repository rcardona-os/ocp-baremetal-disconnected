# Create a Public IP for Internet Access
resource "azurerm_public_ip" "private_vm_public_ip" {
  name                = "private-vm-public-ip"
  location            = azurerm_resource_group.private_rg.location
  resource_group_name = azurerm_resource_group.private_rg.name
  allocation_method   = "Static"  # Use "Static" instead of "Dynamic" for Standard SKU
  sku                 = "Standard"  # Specify Standard SKU if needed
  domain_name_label   = "registry-ocp"  # Set a unique DNS label here
}

# Define a Network Interface
resource "azurerm_network_interface" "private_vm_nic" {
  name                = "private-vm-nic"
  location            = azurerm_resource_group.private_rg.location
  resource_group_name = azurerm_resource_group.private_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.registry_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.private_vm_public_ip.id
  }
}

# Associate the Network Security Group with the Network Interface
resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.private_vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Define the Virtual Machine (VM)
resource "azurerm_linux_virtual_machine" "private_vm" {
  name                = "private-ocp-vm"
  location            = azurerm_resource_group.private_rg.location
  resource_group_name = azurerm_resource_group.private_rg.name
  size                = "Standard_B2as_v2"  # 2 vCPUs, 8 GB RAM
  admin_username      = "ocpuser"

  network_interface_ids = [
    azurerm_network_interface.private_vm_nic.id
  ]

  admin_ssh_key {
    username   = "ocpuser"
    public_key = file("~/.ssh/id_rsa.pub")  # Path to your SSH public key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 300  # Increase the disk size to 128GB
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9_2"
    version   = "latest"
  }

  computer_name  = "private-ocp-vm"
  disable_password_authentication = true
}
