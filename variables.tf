# ── Location & Resource Group ──────────────────────────────────────────────

variable "create_resource_group" {
  description = "Create the firewall resource group. Set false to deploy into an existing resource group."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group for the firewall resources (created or existing, per create_resource_group)."
  type        = string
}

variable "location" {
  description = "Azure region. Used only when create_resource_group = true; otherwise the existing resource group's region is used. The region must support availability zones."
  type        = string
  default     = "East US"
}

# ── Networking ─────────────────────────────────────────────────────────────

variable "vnet_name" {
  description = "Name of the existing VNet to deploy the firewalls into."
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group containing the VNet (may differ from resource_group_name)."
  type        = string
}

# ── Subnet toggles ─────────────────────────────────────────────────────────
# true  = Terraform creates the subnet (its *_subnet_cidr is required)
# false = use an existing subnet with the given name

variable "create_management_subnet" {
  description = "Create the management subnet. Set false to use an existing subnet."
  type        = bool
  default     = false
}

variable "create_untrust_subnet" {
  description = "Create the untrust subnet. Set false to use an existing subnet."
  type        = bool
  default     = false
}

variable "create_trust_subnet" {
  description = "Create the trust subnet. Set false to use an existing subnet."
  type        = bool
  default     = false
}

variable "create_ha2_subnet" {
  description = "Create the HA2 subnet. Set false to use an existing subnet."
  type        = bool
  default     = true
}

# ── Subnet names ───────────────────────────────────────────────────────────

variable "subnet_management_name" {
  description = "Name of the management subnet."
  type        = string
  default     = "snet-fw-mgmt"
}

variable "subnet_untrust_name" {
  description = "Name of the untrust (WAN) subnet."
  type        = string
  default     = "snet-fw-untrust"
}

variable "subnet_trust_name" {
  description = "Name of the trust (LAN) subnet."
  type        = string
  default     = "snet-fw-trust"
}

variable "ha2_subnet_name" {
  description = "Name of the HA2 subnet."
  type        = string
  default     = "snet-fw-ha2"
}

# ── Subnet CIDRs (required only when the matching create_* toggle is true) ─

variable "management_subnet_cidr" {
  description = "CIDR for the management subnet. Required when create_management_subnet = true."
  type        = string
  default     = ""

  validation {
    condition     = var.management_subnet_cidr == "" || can(cidrhost(var.management_subnet_cidr, 0))
    error_message = "management_subnet_cidr must be a valid CIDR block."
  }
}

variable "untrust_subnet_cidr" {
  description = "CIDR for the untrust subnet. Required when create_untrust_subnet = true."
  type        = string
  default     = ""

  validation {
    condition     = var.untrust_subnet_cidr == "" || can(cidrhost(var.untrust_subnet_cidr, 0))
    error_message = "untrust_subnet_cidr must be a valid CIDR block."
  }
}

variable "trust_subnet_cidr" {
  description = "CIDR for the trust subnet. Required when create_trust_subnet = true."
  type        = string
  default     = ""

  validation {
    condition     = var.trust_subnet_cidr == "" || can(cidrhost(var.trust_subnet_cidr, 0))
    error_message = "trust_subnet_cidr must be a valid CIDR block."
  }
}

variable "ha2_subnet_cidr" {
  description = "CIDR for the HA2 subnet. Required when create_ha2_subnet = true. Minimum /28."
  type        = string
  default     = ""

  validation {
    condition     = var.ha2_subnet_cidr == "" || can(cidrhost(var.ha2_subnet_cidr, 0))
    error_message = "ha2_subnet_cidr must be a valid CIDR block."
  }
}

# ── Internal LB ────────────────────────────────────────────────────────────

variable "internal_lb_frontend_ip" {
  description = "Static private IP for the internal LB frontend. Must be inside the trust subnet and not already in use."
  type        = string

  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.internal_lb_frontend_ip))
    error_message = "internal_lb_frontend_ip must be a valid IPv4 address."
  }
}

# ── Firewall VMs ───────────────────────────────────────────────────────────

variable "fw1_name" {
  description = "Name for the first (active) firewall VM, deployed in zone 1."
  type        = string
  default     = "vmseries-fw1"
}

variable "fw2_name" {
  description = "Name for the second (passive) firewall VM, deployed in zone 2."
  type        = string
  default     = "vmseries-fw2"
}

variable "vm_size" {
  description = "Azure VM size. Must support 4 NICs, accelerated networking and Premium storage."
  type        = string
  default     = "Standard_D8s_v3"
}

variable "license_type" {
  description = "VM-Series license SKU: byol, bundle1, or bundle2."
  type        = string
  default     = "bundle1"

  validation {
    condition     = contains(["byol", "bundle1", "bundle2"], var.license_type)
    error_message = "license_type must be byol, bundle1, or bundle2."
  }
}

variable "panos_version" {
  description = "PAN-OS image version. Use 'latest' or pin a specific version (e.g. '11.1.4'); pinning is recommended for production."
  type        = string
  default     = "latest"
}

variable "ssh_public_key" {
  description = "OpenSSH-format public key for the firewall admin account (e.g. 'ssh-rsa AAAA...')."
  type        = string

  validation {
    condition     = can(regex("^ssh-[a-z0-9-]+ [A-Za-z0-9+/=]+", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH-format public key (e.g. 'ssh-rsa AAAA...'), not a PuTTY .ppk or PEM key."
  }
}

# ── Administration ─────────────────────────────────────────────────────────

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the management interfaces on SSH (22) and HTTPS (443). Avoid 0.0.0.0/0 in production."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0))])
    error_message = "admin_cidrs must contain at least one valid CIDR block."
  }
}

# ── Panorama ───────────────────────────────────────────────────────────────

variable "panorama_server" {
  description = "Primary Panorama server IP or FQDN."
  type        = string
}

variable "panorama_server_2" {
  description = "Secondary Panorama server IP or FQDN. Leave empty if none."
  type        = string
  default     = ""
}

variable "panorama_vm_auth_key" {
  description = "VM auth key from Panorama (request bootstrap vm-auth-key generate lifetime <hours>). Set as a sensitive variable."
  type        = string
  sensitive   = true
}

variable "panorama_master_key" {
  description = "Panorama master key, if a non-default master key is configured. Leave empty otherwise."
  type        = string
  default     = ""
  sensitive   = true
}

variable "template_stack_name" {
  description = "Panorama template stack to assign the firewalls to."
  type        = string
}

variable "device_group_name" {
  description = "Panorama device group to assign the firewalls to."
  type        = string
}

# ── Load Balancers ─────────────────────────────────────────────────────────

variable "lb_health_probe_port" {
  description = "TCP port for both LB health probes. Must be allowed by a PAN-OS interface management profile on ethernet1/1 and ethernet1/2."
  type        = number
  default     = 80

  validation {
    condition     = var.lb_health_probe_port >= 1 && var.lb_health_probe_port <= 65535
    error_message = "lb_health_probe_port must be between 1 and 65535."
  }
}

variable "external_lb_ports" {
  description = "TCP ports forwarded by the external (public) LB. Azure does not allow HA-ports rules on public LBs, so list each port."
  type        = list(number)
  default     = [80, 443]

  validation {
    condition     = length(var.external_lb_ports) > 0 && alltrue([for p in var.external_lb_ports : p >= 1 && p <= 65535])
    error_message = "external_lb_ports must contain at least one port between 1 and 65535."
  }
}

variable "tags" {
  description = "Tags applied to all resources created by this template."
  type        = map(string)
  default     = {}
}
