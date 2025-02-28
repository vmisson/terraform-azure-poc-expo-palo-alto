data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "rg-poc-palo-001"
  location = var.region
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-001"
  location            = var.region
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
}

resource "azurerm_subnet" "management" {
  name                 = "subnet-management"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.address_space, 2, 0)]
}

resource "azurerm_subnet" "untrust" {
  name                 = "subnet-untrust"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.address_space, 1, 1)]
}

resource "azurerm_subnet" "trust" {
  name                 = "subnet-trust"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.address_space, 2, 1)]
}

locals {
  ip_configurations = [
    for i in range(0, var.ip_count) : {
      id   = i
      name = "ipconfig${i}"
    }
  ]
}

resource "azurerm_public_ip" "untrust" {
  count               = var.ip_count
  name                = "${var.firewall_name}-untrust-nic-${format("%03d", count.index + 1)}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.region
  allocation_method   = "Static"
  domain_name_label   = "fw1-${uuidv5("dns", data.azurerm_client_config.current.subscription_id)}-${format("%03d", count.index + 1)}"
}

resource "azurerm_network_interface" "untrust" {
  name                           = "${var.firewall_name}-untrust-nic-001"
  location                       = var.region
  resource_group_name            = azurerm_resource_group.this.name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = true

  dynamic "ip_configuration" {
    for_each = local.ip_configurations
    content {
      name                          = ip_configuration.value["name"]
      subnet_id                     = azurerm_subnet.untrust.id
      private_ip_address_allocation = "Dynamic"
      primary                       = ip_configuration.value["name"] == "ipconfig0" ? true : false
      public_ip_address_id          = azurerm_public_ip.untrust[ip_configuration.value["id"]].id
    }
  }
}

resource "azurerm_public_ip" "management" {
  name                = "${var.firewall_name}-mgmt-pip-001"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.region
  allocation_method   = "Static"
  domain_name_label   = "fw1-${uuidv5("dns", data.azurerm_client_config.current.subscription_id)}-mgmt"
}

resource "azurerm_network_interface" "management" {
  name                = "${var.firewall_name}-mgmt-nic-001"
  location            = var.region
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig0"
    subnet_id                     = azurerm_subnet.management.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.management.id
  }
}

resource "azurerm_network_interface" "trust" {
  name                           = "${var.firewall_name}-trust-nic-001"
  location                       = var.region
  resource_group_name            = azurerm_resource_group.this.name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "ipconfig0"
    subnet_id                     = azurerm_subnet.trust.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "random_password" "this" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = var.firewall_name
  location            = var.region
  resource_group_name = azurerm_resource_group.this.name

  size = var.size
  network_interface_ids = [
    azurerm_network_interface.management.id,
    azurerm_network_interface.untrust.id,
    azurerm_network_interface.trust.id
  ]

  admin_username                  = var.username
  admin_password                  = random_password.this.result
  disable_password_authentication = false

  os_disk {
    name                 = "${var.firewall_name}-osd-001"
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
  }

  source_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = "byol"
    version   = "latest"
  }

  plan {
    name      = "byol"
    publisher = "paloaltonetworks"
    product   = "vmseries-flex"
  }

  custom_data = var.bootstrap_options == null ? null : base64encode(var.bootstrap_options)

  boot_diagnostics {
  }
}

resource "azurerm_network_security_group" "management" {
  name                = "subnet-management-nsg-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "A-IN-ALLOW-ALL"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "data" {
  name                = "subnet-data-nsg-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "A-IN-ALLOW-ALL"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.untrust.id
  network_security_group_id = azurerm_network_security_group.data.id
}

resource "azurerm_virtual_network" "spoke" {
  count               = var.spoke_count
  name                = "vnet-spoke-${format("%03d", count.index + 1)}"
  location            = var.region
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.200.${count.index + 1}.0/24"]
}

resource "azurerm_subnet" "workload" {
  count                = var.spoke_count
  name                 = "subnet-workload"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.spoke[count.index].name
  address_prefixes     = [cidrsubnet("10.200.${count.index + 1}.0/24", 1, 0)]
}

resource "azurerm_network_interface" "workload" {
  count               = var.spoke_count
  name                = "vm-spoke-${format("%03d", count.index + 1)}-nic-001"
  location            = var.region
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload[count.index].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "workload" {
  count                           = var.spoke_count
  name                            = "vm-spoke-${format("%03d", count.index + 1)}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = var.region
  size                            = "Standard_B2s"
  admin_username                  = "azureuser"
  admin_password                  = random_password.this.result
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.workload[count.index].id,
  ]

  os_disk {
    name                 = "vm-spoke-${format("%03d", count.index + 1)}-osd-001"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  boot_diagnostics {
  }
}

resource "azurerm_virtual_network_peering" "hub-to-spoke" {
  count                        = var.spoke_count
  name                         = "hub-to-spoke-${format("%03d", count.index + 1)}"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[count.index].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke-to-hub" {
  count                        = var.spoke_count
  name                         = "spoke-to-hub-${format("%03d", count.index + 1)}"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.spoke[count.index].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_route_table" "spoke" {
  name                = "rt-spoke-001"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.region
}

resource "azurerm_route" "default" {
  name                   = "default"
  resource_group_name    = azurerm_resource_group.this.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_network_interface.trust.private_ip_address
}

resource "azurerm_subnet_route_table_association" "spoke" {
  count          = var.spoke_count
  subnet_id      = azurerm_subnet.workload[count.index].id
  route_table_id = azurerm_route_table.spoke.id
}