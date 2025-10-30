terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "subscriptionidhere"
}

provider "azuread" {}

# ---------- Variables ----------
variable "prefix" {
  type    = string
  default = "mandar"
}

variable "location" {
  type    = string
  default = "eastus"
}

# ---------- Resource Group ----------
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# ---------- Network ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.240.0.0/16"]
}

# ---------- Storage ----------
resource "azurerm_storage_account" "sa" {
  name                     = lower(replace("${var.prefix}sa${substr(md5(timestamp()), 0, 6)}", "-", ""))
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "backup" {
  name                  = "kasten-backups"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# ---------- Azure AD App + Service Principal ----------
resource "azuread_application" "kasten_app" {
  display_name = "${var.prefix}-kasten-app"
}

resource "azuread_service_principal" "kasten_sp" {
  client_id = azuread_application.kasten_app.client_id
}

resource "azuread_service_principal_password" "kasten_sp_pwd" {
  service_principal_id = azuread_service_principal.kasten_sp.id
  end_date             = timeadd(timestamp(), "8760h") # 1 year
}

# ---------- AKS Cluster ----------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-dns"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }

  sku_tier = "Free"

  tags = {
    environment = "demo"
  }
}

# ---------- Role Assignments ----------
resource "azurerm_role_assignment" "aks_storage_access" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

resource "azurerm_role_assignment" "kasten_sp_storage_access" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.kasten_sp.id
}

# ---------- Outputs ----------
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "storage_container_name" {
  value = azurerm_storage_container.backup.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "kubeconfig" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "kasten_sp_client_id" {
  value = azuread_application.kasten_app.client_id
}

output "kasten_sp_client_secret" {
  value     = azuread_service_principal_password.kasten_sp_pwd.value
  sensitive = true
}
