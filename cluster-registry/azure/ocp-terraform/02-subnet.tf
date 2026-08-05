resource "azurerm_subnet" "registry_subnet" {
  name                 = "registry-subnet"
  resource_group_name  = azurerm_resource_group.private_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]  # Replace with your actual subnet range
}

resource "azurerm_virtual_network" "vnet" {
  name                = "private-vnet"
  location            = azurerm_resource_group.private_rg.location
  resource_group_name = azurerm_resource_group.private_rg.name
  address_space       = ["10.0.0.0/16"]  # Replace with your actual address space
}