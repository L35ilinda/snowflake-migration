output "name" {
  value       = snowflake_storage_integration.this.name
  description = "Name of the created storage integration."
}

output "azure_consent_url" {
  value       = snowflake_storage_integration.this.azure_consent_url
  description = "One-time URL for an Azure admin to grant consent to the Snowflake service principal."
}

output "azure_multi_tenant_app_name" {
  value       = snowflake_storage_integration.this.azure_multi_tenant_app_name
  description = "The Snowflake service principal name to grant Storage Blob Data Reader."
}
