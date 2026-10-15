provider "azurerm" {
  features {}
}

# Prerequisite: accept the Marketplace agreement once per subscription per license type:
#   az vm image terms accept --publisher paloaltonetworks --offer vmseries-flex --plan <license_type>

# ── Resource Group (create or use existing) ────────────────────────────────

resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "main" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

# ── Existing VNet ──────────────────────────────────────────────────────────

data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name
}

# ── Subnets (create or use existing per toggle) ────────────────────────────

data "azurerm_subnet" "management_existing" {
  count                = var.create_management_subnet ? 0 : 1
  name                 = var.subnet_management_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = var.vnet_resource_group_name
}

resource "azurerm_subnet" "management_new" {
  count                = var.create_management_subnet ? 1 : 0
  name                 = var.subnet_management_name
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  address_prefixes     = [var.management_subnet_cidr]

  lifecycle {
    precondition {
      condition     = var.management_subnet_cidr != ""
      error_message = "management_subnet_cidr is required when create_management_subnet = true."
    }
  }
}

data "azurerm_subnet" "untrust_existing" {
  count                = var.create_untrust_subnet ? 0 : 1
  name                 = var.subnet_untrust_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = var.vnet_resource_group_name
}

resource "azurerm_subnet" "untrust_new" {
  count                = var.create_untrust_subnet ? 1 : 0
  name                 = var.subnet_untrust_name
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  address_prefixes     = [var.untrust_subnet_cidr]

  lifecycle {
    precondition {
      condition     = var.untrust_subnet_cidr != ""
      error_message = "untrust_subnet_cidr is required when create_untrust_subnet = true."
    }
  }
}

data "azurerm_subnet" "trust_existing" {
  count                = var.create_trust_subnet ? 0 : 1
  name                 = var.subnet_trust_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = var.vnet_resource_group_name
}

resource "azurerm_subnet" "trust_new" {
  count                = var.create_trust_subnet ? 1 : 0
  name                 = var.subnet_trust_name
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  address_prefixes     = [var.trust_subnet_cidr]

  lifecycle {
    precondition {
      condition     = var.trust_subnet_cidr != ""
      error_message = "trust_subnet_cidr is required when create_trust_subnet = true."
    }
  }
}

data "azurerm_subnet" "ha2_existing" {
  count                = var.create_ha2_subnet ? 0 : 1
  name                 = var.ha2_subnet_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = var.vnet_resource_group_name
}

resource "azurerm_subnet" "ha2_new" {
  count                = var.create_ha2_subnet ? 1 : 0
  name                 = var.ha2_subnet_name
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  address_prefixes     = [var.ha2_subnet_cidr]

  lifecycle {
    precondition {
      condition     = var.ha2_subnet_cidr != ""
      error_message = "ha2_subnet_cidr is required when create_ha2_subnet = true."
    }
  }
}

locals {
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.main[0].name : data.azurerm_resource_group.main[0].name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.main[0].location : data.azurerm_resource_group.main[0].location

  management_subnet_id = var.create_management_subnet ? azurerm_subnet.management_new[0].id : data.azurerm_subnet.management_existing[0].id
  untrust_subnet_id    = var.create_untrust_subnet ? azurerm_subnet.untrust_new[0].id : data.azurerm_subnet.untrust_existing[0].id
  trust_subnet_id      = var.create_trust_subnet ? azurerm_subnet.trust_new[0].id : data.azurerm_subnet.trust_existing[0].id
  ha2_subnet_id        = var.create_ha2_subnet ? azurerm_subnet.ha2_new[0].id : data.azurerm_subnet.ha2_existing[0].id

  init_cfg = join("\n", compact([
    "type=dhcp-client",
    "panorama-server=${var.panorama_server}",
    var.panorama_server_2 != "" ? "panorama-server-2=${var.panorama_server_2}" : "",
    "tplname=${var.template_stack_name}",
    "dgname=${var.device_group_name}",
    "vm-auth-key=${var.panorama_vm_auth_key}",
    var.panorama_master_key != "" ? "masterkey=${var.panorama_master_key}" : "",
  ]))
}

# ── NSGs ───────────────────────────────────────────────────────────────────

resource "azurerm_network_security_group" "management" {
  name                = "mgmt-nsg"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.admin_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.admin_cidrs
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# 168.63.129.16 is Azure's health probe source IP — must be allowed or the LB
# marks both firewalls unhealthy and silently drops all traffic.
resource "azurerm_network_security_group" "untrust" {
  name                = "untrust-nsg"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "allow-azure-lb-probe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.lb_health_probe_port)
    source_address_prefix      = "168.63.129.16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-inbound-lb-traffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [for p in var.external_lb_ports : tostring(p)]
    source_address_prefix      = "*"
    destination_address_prefix = azurerm_public_ip.external_lb.ip_address
  }

  tags = var.tags
}

resource "azurerm_network_security_group" "trust" {
  name                = "trust-nsg"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "allow-azure-lb-probe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.lb_health_probe_port)
    source_address_prefix      = "168.63.129.16"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = local.management_subnet_id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "untrust" {
  subnet_id                 = local.untrust_subnet_id
  network_security_group_id = azurerm_network_security_group.untrust.id
}

resource "azurerm_subnet_network_security_group_association" "trust" {
  subnet_id                 = local.trust_subnet_id
  network_security_group_id = azurerm_network_security_group.trust.id
}

# ── Public IPs ─────────────────────────────────────────────────────────────

# Zone-pinned to match their respective firewall VM zone
resource "azurerm_public_ip" "management" {
  count               = 2
  name                = "mgmt-pip-fw${count.index + 1}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [count.index == 0 ? "1" : "2"]

  tags = var.tags
}

# Zone-redundant (no zone specified) — serves both firewalls
resource "azurerm_public_ip" "external_lb" {
  name                = "external-lb-pip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# ── Network interfaces ─────────────────────────────────────────────────────
# count = 2 throughout — index 0 = FW1 (zone 1), index 1 = FW2 (zone 2)
# NIC order per VM: management first (eth0), then data plane

resource "azurerm_network_interface" "management" {
  count               = 2
  name                = "mgmt-nic-fw${count.index + 1}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "mgmt-ip"
    subnet_id                     = local.management_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.management[count.index].id
  }

  tags = var.tags
}

resource "azurerm_network_interface" "untrust" {
  count                          = 2
  name                           = "untrust-nic-fw${count.index + 1}"
  location                       = local.resource_group_location
  resource_group_name            = local.resource_group_name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "untrust-ip"
    subnet_id                     = local.untrust_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_network_interface" "trust" {
  count                          = 2
  name                           = "trust-nic-fw${count.index + 1}"
  location                       = local.resource_group_location
  resource_group_name            = local.resource_group_name
  ip_forwarding_enabled          = true
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = "trust-ip"
    subnet_id                     = local.trust_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_network_interface" "ha2" {
  count               = 2
  name                = "ha2-nic-fw${count.index + 1}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "ha2-ip"
    subnet_id                     = local.ha2_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

# ── Firewalls ──────────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "firewall" {
  count               = 2
  name                = count.index == 0 ? var.fw1_name : var.fw2_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  size                = var.vm_size
  admin_username      = "panadmin"
  zone                = count.index == 0 ? "1" : "2"

  # NIC order is critical: management must be index 0 (eth0)
  network_interface_ids = [
    azurerm_network_interface.management[count.index].id,
    azurerm_network_interface.untrust[count.index].id,
    azurerm_network_interface.trust[count.index].id,
    azurerm_network_interface.ha2[count.index].id,
  ]

  admin_ssh_key {
    username   = "panadmin"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  plan {
    name      = var.license_type
    publisher = "paloaltonetworks"
    product   = "vmseries-flex"
  }

  source_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = var.license_type
    version   = var.panos_version
  }

  custom_data = base64encode(local.init_cfg)

  provision_vm_agent              = false
  allow_extension_operations      = false
  disable_password_authentication = true

  tags = merge(var.tags, {
    Name = count.index == 0 ? var.fw1_name : var.fw2_name
  })
}

# ── External Load Balancer (untrust / WAN side) ────────────────────────────

resource "azurerm_lb" "external" {
  name                = "external-lb"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "external-lb-frontend"
    public_ip_address_id = azurerm_public_ip.external_lb.id
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "external" {
  name            = "external-lb-backend"
  loadbalancer_id = azurerm_lb.external.id
}

resource "azurerm_lb_probe" "external" {
  name            = "external-lb-probe"
  loadbalancer_id = azurerm_lb.external.id
  protocol        = "Tcp"
  port            = var.lb_health_probe_port
}

resource "azurerm_lb_rule" "external" {
  for_each = toset([for p in var.external_lb_ports : tostring(p)])

  name                           = "external-lb-rule-tcp${each.key}"
  loadbalancer_id                = azurerm_lb.external.id
  protocol                       = "Tcp"
  frontend_port                  = tonumber(each.key)
  backend_port                   = tonumber(each.key)
  frontend_ip_configuration_name = "external-lb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.external.id]
  probe_id                       = azurerm_lb_probe.external.id
  floating_ip_enabled            = true
}

resource "azurerm_network_interface_backend_address_pool_association" "untrust" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.untrust[count.index].id
  ip_configuration_name   = "untrust-ip"
  backend_address_pool_id = azurerm_lb_backend_address_pool.external.id
}

# ── Internal Load Balancer (trust / LAN side) ──────────────────────────────

resource "azurerm_lb" "internal" {
  name                = "internal-lb"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "internal-lb-frontend"
    subnet_id                     = local.trust_subnet_id
    private_ip_address            = var.internal_lb_frontend_ip
    private_ip_address_allocation = "Static"
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "internal" {
  name            = "internal-lb-backend"
  loadbalancer_id = azurerm_lb.internal.id
}

resource "azurerm_lb_probe" "internal" {
  name            = "internal-lb-probe"
  loadbalancer_id = azurerm_lb.internal.id
  protocol        = "Tcp"
  port            = var.lb_health_probe_port
}

resource "azurerm_lb_rule" "internal" {
  name                           = "internal-lb-rule-all"
  loadbalancer_id                = azurerm_lb.internal.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "internal-lb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.internal.id]
  probe_id                       = azurerm_lb_probe.internal.id
  floating_ip_enabled            = true
}

resource "azurerm_network_interface_backend_address_pool_association" "trust" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.trust[count.index].id
  ip_configuration_name   = "trust-ip"
  backend_address_pool_id = azurerm_lb_backend_address_pool.internal.id
}
