output "storage_integration_name" {
  value       = module.storage_integration.name
  description = "Name of the Snowflake storage integration."
}

output "storage_integration_azure_consent_url" {
  value       = module.storage_integration.azure_consent_url
  description = "One-time URL to grant Azure admin consent to the Snowflake service principal."
}

output "storage_integration_azure_multi_tenant_app_name" {
  value       = module.storage_integration.azure_multi_tenant_app_name
  description = "Identity to grant Storage Blob Data Reader on the target storage account."
}

output "database_name" {
  value       = module.database_layers.database_name
  description = "Analytics database name."
}

output "raw_schema_names" {
  value       = module.database_layers.raw_schema_names
  description = "Map of company_id to RAW schema name."
}

output "company_stage_fully_qualified_names" {
  value       = { for company_id, ingest in module.company_ingest : company_id => ingest.stage_fully_qualified_name }
  description = "Map of company_id to stage FQN. Use in LIST / COPY INTO."
}
