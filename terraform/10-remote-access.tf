# 10-remote-access.tf – Bastion, JumpBox, (optional) VPN Gateway

# TLS key generation if no key provided
resource "tls_private_key" "jumpbox" {
  count      = var.enable_jumpbox && var.jumpbox_ssh_public_key == "" ? 1 : 0
  algorithm  = "RSA"
  rsa_bits   = 4096
}

# JumpBox public key to use
locals {
  jumpbox_public_key = var.jumpbox_ssh_public_key != "" ? var.jumpbox_ssh_public_key : (var.enable_jumpbox ? tls_private_key.jumpbox[0].public_key_openssh : "")
}

# Bastion Public IP
resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.ai_prefix}-bastion-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Bastion Host
resource "azurerm_bastion_host" "main" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.ai_prefix}-bastion"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

# NSG for JumpBox (allow SSH only from Bastion subnet)
resource "azurerm_network_security_group" "jumpbox" {
  count               = var.enable_jumpbox ? 1 : 0
  name                = "${var.ai_prefix}-jump-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowSSHFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = azurerm_subnet.bastion[0].address_prefixes[0]
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowOutboundInternet443"
    priority                   = 500
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_network_interface" "jumpbox" {
  count               = var.enable_jumpbox ? 1 : 0
  name                = "${var.ai_prefix}-jump-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpbox[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "jumpbox" {
  count                     = var.enable_jumpbox ? 1 : 0
  network_interface_id      = azurerm_network_interface.jumpbox[0].id
  network_security_group_id = azurerm_network_security_group.jumpbox[0].id
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count                 = var.enable_jumpbox ? 1 : 0
  name                  = "${var.ai_prefix}-jumpbox"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = "Standard_B2s"
  admin_username        = var.jumpbox_admin_username
  disable_password_authentication = true
  network_interface_ids = [azurerm_network_interface.jumpbox[0].id]

  admin_ssh_key {
    username   = var.jumpbox_admin_username
    public_key = local.jumpbox_public_key
  }

  os_disk {
    name                 = "${var.ai_prefix}-jump-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# VPN Gateway (conditional skeleton)
resource "azurerm_public_ip" "vpngw" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = "${var.ai_prefix}-vpngw-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "p2s" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = "${var.ai_prefix}-vpngw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = false
  sku                 = "VpnGw1"

  ip_configuration {
    name                          = "vpngw"
    public_ip_address_id          = azurerm_public_ip.vpngw[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  vpn_client_configuration {
    address_space = var.vpn_p2s_address_space
    dynamic "root_certificate" {
      for_each = var.vpn_root_cert_data != "" ? [1] : []
      content {
        name             = var.vpn_root_cert_name
        public_cert_data = var.vpn_root_cert_data
      }
    }
  }
}
# Outputs for remote access will be added in outputs.tf
