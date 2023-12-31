locals {
  ip_allocation_method  = "Dynamic"
  ip_name               = "${var.name}-ip"
  active_active_ip_name = "${var.name}-aa-ip"
}

resource "azurerm_public_ip" "ip" {
  name                = local.ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = local.ip_allocation_method

  lifecycle {
    ignore_changes = [tags["CreationDateTime"], tags["Environment"]]
  }
}

resource "azurerm_public_ip" "active_active_ip" {
  count = var.active_active ? 1 : 0

  name                = local.active_active_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = local.ip_allocation_method

  lifecycle {
    ignore_changes = [tags["CreationDateTime"], tags["Environment"]]
  }
}

locals {
  aad_tenant                          = sensitive("https://login.microsoftonline.com/${var.aad_tenant}/")
  aad_issuer                          = sensitive("https://sts.windows.net/${var.aad_tenant}/")
  default_ip_configuration_name       = "default"
  active_active_ip_configuration_name = "active-active"
}

resource "azurerm_virtual_network_gateway" "vnet_gateway" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = var.type
  vpn_type            = var.vpn_type
  sku                 = var.sku
  generation          = var.generation
  active_active       = var.active_active

  ip_configuration {
    name                          = local.default_ip_configuration_name
    private_ip_address_allocation = local.ip_allocation_method
    subnet_id                     = var.subnet_id
    public_ip_address_id          = azurerm_public_ip.ip.id
  }

  dynamic "ip_configuration" {
    for_each = var.active_active ? [true] : []

    content {
      name                          = local.active_active_ip_configuration_name
      private_ip_address_allocation = local.ip_allocation_method
      subnet_id                     = var.subnet_id
      public_ip_address_id          = azurerm_public_ip.active_active_ip[0].id
    }
  }

  dynamic "vpn_client_configuration" {
    for_each = var.vpn_address_space == null ? [] : [true]

    content {
      address_space        = var.vpn_address_space
      vpn_client_protocols = var.vpn_client_protocols
      vpn_auth_types       = var.vpn_auth_types

      aad_tenant   = local.aad_tenant
      aad_audience = var.aad_audience
      aad_issuer   = local.aad_issuer

      radius_server_address = var.radius_server_address
      radius_server_secret  = var.radius_server_secret

      dynamic "root_certificate" {
        for_each = var.root_certificate == null ? [] : [true]

        content {
          name             = var.root_certificate.name
          public_cert_data = var.root_certificate.public_cert_data
        }
      }

      dynamic "revoked_certificate" {
        for_each = var.revoked_certificate == null ? [] : [true]

        content {
          name       = var.revoked_certificate.name
          thumbprint = var.revoked_certificate.thumbprint
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [tags["CreationDateTime"], tags["Environment"]]
  }
}

locals {
  vnet_gateway_diagnostic_name     = "${azurerm_virtual_network_gateway.vnet_gateway.name}-diagnostic"
  ip_diagnostic_name               = "${azurerm_public_ip.ip.name}-diagnostic"
  active_active_ip_diagnostic_name = try("${azurerm_public_ip.active_active_ip[0].name}-diagnostic", null)
}

module "vnet_gateway_diagnostic" {
  source = "github.com/danielkhen/diagnostic_setting_module"

  name                       = local.vnet_gateway_diagnostic_name
  target_resource_id         = azurerm_virtual_network_gateway.vnet_gateway.id
  log_analytics_workspace_id = var.log_analytics_id
}

module "ip_diagnostic" {
  source = "github.com/danielkhen/diagnostic_setting_module"

  name                       = local.ip_diagnostic_name
  target_resource_id         = azurerm_public_ip.ip.id
  log_analytics_workspace_id = var.log_analytics_id
}

module "active_active_ip_diagnostic" {
  source = "github.com/danielkhen/diagnostic_setting_module"
  count  = var.active_active ? 1 : 0

  name                       = local.active_active_ip_diagnostic_name
  target_resource_id         = azurerm_public_ip.active_active_ip[0].id
  log_analytics_workspace_id = var.log_analytics_id
}