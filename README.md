# Palo Alto VM-Series Active/Passive HA on Azure

Terraform template that deploys a pair of Palo Alto VM-Series firewalls in an Active/Passive HA configuration on Azure, bootstrapped to Panorama.

## Architecture

- **FW1** (zone 1) and **FW2** (zone 2) — spread across availability zones for zone-level redundancy
- **4 NICs per firewall**: management (eth0), untrust (ethernet1/1), trust (ethernet1/2), HA2 (ethernet1/3)
- **External LB** (Standard, public) — internet-facing, untrust side
- **Internal LB** (Standard, private, HA ports) — trust side, next hop for spoke route tables
- **HA1** over the management interface, **HA2** over a dedicated subnet
- **Bootstrap** via `custom_data` (init-cfg): registers both firewalls with Panorama and assigns the template stack and device group
- NSGs on the management, untrust and trust subnets (management restricted to `admin_cidrs`)

The template deploys into an **existing VNet**. The resource group and each of the four subnets can be either created by Terraform or reused:

| Setting | `true` | `false` |
|---|---|---|
| `create_resource_group` | Creates `resource_group_name` in `location` | Uses the existing resource group |
| `create_management_subnet` / `create_untrust_subnet` / `create_trust_subnet` / `create_ha2_subnet` | Creates the subnet; its `*_subnet_cidr` is required | Uses the existing subnet of that name |

By default the management, untrust and trust subnets are reused and the HA2 subnet is created.

## Prerequisites

**1. Accept the Marketplace terms** (once per subscription, per license type):
```bash
az vm image terms accept \
  --publisher paloaltonetworks \
  --offer vmseries-flex \
  --plan <license_type>   # byol | bundle1 | bundle2
```

**2. An existing VNet** in a region that supports availability zones, with free space for any subnets Terraform should create.

**3. Panorama**, prepared before applying:
- Device group matching `device_group_name`
- Template stack matching `template_stack_name`
- A VM auth key (`request bootstrap vm-auth-key generate lifetime <hours>`)

**4. Azure credentials** — a service principal (or other identity) with Contributor on the firewall resource group and Network Contributor on the VNet:
```bash
az ad sp create-for-rbac \
  --name "terraform-vmseries" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id>
```

**5. Quota** for 2 × `vm_size` in the target region (Standard_D8s_v3 by default = 16 vCPUs of the DSv3 family).

## Quick start

**1. Create a repo from this template** and clone it.

**2. Set the variables.** Either copy the example file:
```bash
cp terraform.tfvars.example terraform.tfvars   # git-ignored
```
or set the same values as workspace variables in HCP Terraform.

Required variables (no default): `resource_group_name`, `vnet_name`, `vnet_resource_group_name`, `internal_lb_frontend_ip`, `ssh_public_key`, `admin_cidrs`, `panorama_server`, `panorama_vm_auth_key`, `template_stack_name`, `device_group_name`.

**3. Choose where state lives.** For HCP Terraform, add a `cloud` block to `terraform.tf` with your organization and workspace, then:
```bash
terraform login
terraform init
```
For local state, just run `terraform init`.

In HCP Terraform, set these as **environment variables** on the workspace:

| Variable | Value |
|---|---|
| `ARM_CLIENT_ID` | Service principal app ID |
| `ARM_CLIENT_SECRET` | Service principal secret (sensitive) |
| `ARM_TENANT_ID` | Azure tenant ID |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |

and these as **sensitive Terraform variables**: `panorama_vm_auth_key`, `panorama_master_key` (if used).

**4. Plan and apply:**
```bash
terraform plan
terraform apply
```

## Post-deploy configuration

### 1. Interfaces (Panorama template stack)
- `ethernet1/1` — Layer 3, zone `untrust`, DHCP client
- `ethernet1/2` — Layer 3, zone `trust`, DHCP client
- `ethernet1/3` — HA2
- Virtual router with a default route out `ethernet1/1`
- **Interface management profile** on `ethernet1/1` and `ethernet1/2` allowing TCP on `lb_health_probe_port` — required for the Azure LB health probes

### 2. HA (on each firewall, CLI or Panorama)
```
set deviceconfig high-availability enabled yes
set deviceconfig high-availability group group-id 1
set deviceconfig high-availability group mode active-passive
set deviceconfig high-availability interface ha1 port management
set deviceconfig high-availability group peer-ip <peer-mgmt-private-ip>
set deviceconfig high-availability interface ha2 port ethernet1/3
set deviceconfig high-availability interface ha2 transport ethernet
```

### 3. Security policy and NAT (Panorama device group)
- Allow outbound: trust → untrust
- Source NAT: trust → untrust, dynamic IP and port on `ethernet1/1`
- Inbound rules and destination NAT for the `external_lb_ports` as needed

### 4. Spoke route tables
Add a UDR to every subnet that should route through the firewalls:
- Destination: `0.0.0.0/0`
- Next hop type: Virtual appliance
- Next hop IP: `internal_lb_private_ip` (Terraform output)

### 5. Verify
```
show high-availability state
show interface ethernet1/1
show interface ethernet1/2
show panorama-status
```

## Outputs

| Output | Description |
|---|---|
| `fw1_management_public_ip` / `fw2_management_public_ip` | Management public IPs (SSH/HTTPS) |
| `fw1_management_private_ip` / `fw2_management_private_ip` | Management private IPs (HA1 peer IPs) |
| `external_lb_public_ip` | Internet-facing public IP (external LB frontend) |
| `internal_lb_private_ip` | Internal LB frontend IP (next hop for spoke UDRs) |
| `fw1_untrust_private_ip` / `fw2_untrust_private_ip` | ethernet1/1 private IPs |
| `fw1_trust_private_ip` / `fw2_trust_private_ip` | ethernet1/2 private IPs |
| `fw1_ha2_private_ip` / `fw2_ha2_private_ip` | ethernet1/3 (HA2) private IPs |

## Notes

- **Admin account**: the VM is created with admin user `panadmin` and the SSH key from `ssh_public_key`; no password is set.
- **HA2 transport** is Ethernet (Layer 2), so no IP address is needed on the HA2 interface.
- **Passive firewall**: data interfaces on the passive peer are down by design; the Azure LBs send traffic only to the active firewall.
- **bundle1 / bundle2** license automatically at boot through Azure Marketplace; `byol` needs an auth code applied after deployment (or via Panorama).
- **Pin `panos_version`** for production so a re-plan never picks up a new image.
- **ECMP**: if both data interfaces see health probes, enable ECMP on the virtual router (IP hash, symmetric return) so probe replies leave the interface they arrived on.
