data "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = data.azurerm_storage_account.this.id
  container_access_type = each.value.access_type
}