output "container_names" {
  description = "Map of container key -> container name."
  value       = { for k, c in azurerm_storage_container.this : k => c.name }
}

output "container_ids" {
  description = "Map of container key -> Azure resource ID."
  value       = { for k, c in azurerm_storage_container.this : k => c.id }
}

output "storage_account_name" {
  description = "The storage account these containers belong to."
  value       = data.azurerm_storage_account.this.name
}