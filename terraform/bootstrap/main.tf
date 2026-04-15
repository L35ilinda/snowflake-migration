terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  # Local state is intentional: this root creates the container that
  # all other roots use as their remote backend. Chicken-and-egg.
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

data "azurerm_storage_account" "existing" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "tfstate" {
  name                  = var.tfstate_container_name
  storage_account_id    = data.azurerm_storage_account.existing.id
  container_access_type = "private"
}

output "backend_config" {
  description = "Copy these into environments/*/backend.tf if you change any values."
  value = {
    resource_group_name  = var.resource_group_name
    storage_account_name = var.storage_account_name
    container_name       = azurerm_storage_container.tfstate.name
  }
}
