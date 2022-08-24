terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 3.0" 
    }    
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

locals {
    # Azure region to deploy to
    azure_region = "eastus"

    # define the Azure resource names
    resource_name_prefix= "eus-dk-prd-net" # {region}-{org}-{env}-{app}
}

# The Azure Resource group for all the resources to reside
resource azurerm_resource_group "rg" {
    name     = "${local.resource_name_prefix}-rg"
    location = local.azure_region
}

# Azure ExpressRoute Circuit
resource "azurerm_express_route_circuit" "express_route" {
    name                = "${local.resource_name_prefix}-erc"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location

    # https://docs.microsoft.com/en-us/azure/expressroute/expressroute-locations-providers
    service_provider_name   = "Equinix"
    peering_location        = "Washington DC"
    bandwidth_in_mbps       = 1000

    sku {
      tier      = "Standard"
      family    = "MeteredData"
    }
}

# Azure ExpressRoute Private Peering
resource "azurerm_express_route_circuit_peering" "express_route_peering" {
    resource_group_name             = azurerm_resource_group.rg.name
    express_route_circuit_name      = azurerm_express_route_circuit.express_route.name
    peering_type                    = "AzurePrivatePeering"
    primary_peer_address_prefix     = "10.0.0.0/30"
    secondary_peer_address_prefix   = "10.0.0.0/30"
    vlan_id = 100
}

# Azure Virtual Network
resource "azurerm_virtual_network" "virtual_network" {
    name                = "${local.resource_name_prefix}-vnet"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    address_space       = [ "172.16.0.0/12" ]
}

# GatewaySubnet within the Virtual Network
resource "azurerm_subnet" "gateway_subnet" {
    name                    = "GatewaySubnet"
    resource_group_name     = azurerm_resource_group.rg.name
    virtual_network_name    = azurerm_virtual_network.virtual_network.name
    address_prefixes        = [ "172.16.0.0/24" ]
    enforce_private_link_endpoint_network_policies  = true
}

# Azure Public IP Address for the VNet Gateway
resource "azurerm_public_ip" "vnet_gateway_public_ip" {
    name                  = "${local.resource_name_prefix}-vgw-pip"
    resource_group_name   = azurerm_resource_group.rg.name
    location              = azurerm_resource_group.rg.location

    sku               = "Basic"
    allocation_method = "Dynamic"
}

# Azure Virtual Network Gateway
resource azurerm_virtual_network_gateway "virtual_network_gateway" {
    name                = "${local.resource_name_prefix}-vgw"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    type     = "ExpressRoute"
    vpn_type = "PolicyBased"

    sku           = "HighPerformance"
    active_active = false
    enable_bgp    = false

    ip_configuration {
        name                          = "default"
        private_ip_address_allocation = "Dynamic"
        subnet_id                     = azurerm_subnet.gateway_subnet.id
        public_ip_address_id          = azurerm_public_ip.vnet_gateway_public_ip.id
    }
}