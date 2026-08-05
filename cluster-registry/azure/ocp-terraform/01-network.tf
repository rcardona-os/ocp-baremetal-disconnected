# Define the Resource Group
resource "azurerm_resource_group" "private_rg" {
  name     = "private-rg"
  location = "East US"
}

# Define the Network Security Group (NSG) for internet access
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "private-vm-nsg"
  location            = azurerm_resource_group.private_rg.location
  resource_group_name = azurerm_resource_group.private_rg.name

  # Allow SSH
  security_rule {
    name                       = "AllowInboundSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP/HTTPS Outbound
  security_rule {
    name                       = "AllowOutboundInternet"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  # Allow Inbound on Port 443
  security_rule {
    name                       = "AllowInbound443"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # # Allow Inbound on Port 7443
  # security_rule {
  #   name                       = "AllowInbound7443"
  #   priority                   = 1004
  #   direction                  = "Inbound"
  #   access                     = "Allow"
  #   protocol                   = "Tcp"
  #   source_port_range          = "*"
  #   destination_port_range     = "7443"
  #   source_address_prefix      = "*"
  #   destination_address_prefix = "*"
  # }

  # # Allow Inbound on Port 8443
  # security_rule {
  #   name                       = "AllowInbound8080"
  #   priority                   = 1005
  #   direction                  = "Inbound"
  #   access                     = "Allow"
  #   protocol                   = "Tcp"
  #   source_port_range          = "*"
  #   destination_port_range     = "8080"
  #   source_address_prefix      = "*"
  #   destination_address_prefix = "*"
  # }

  # Allow Inbound on Port 8443
  security_rule {
    name                       = "AllowInbound8443"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
