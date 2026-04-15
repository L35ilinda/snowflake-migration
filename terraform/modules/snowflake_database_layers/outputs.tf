output "database_name" {
  value       = snowflake_database.this.name
  description = "Name of the created database."
}

output "raw_schema_names" {
  value       = { for cid, schema in snowflake_schema.raw : cid => schema.name }
  description = "Map of company_id to RAW schema name. Reference as module.x.raw_schema_names[\"01\"]."
}

output "staging_schema_name" {
  value       = snowflake_schema.shared["STAGING"].name
  description = "Name of the STAGING schema."
}

output "core_schema_name" {
  value       = snowflake_schema.shared["CORE"].name
  description = "Name of the CORE schema."
}

output "marts_schema_name" {
  value       = snowflake_schema.shared["MARTS"].name
  description = "Name of the MARTS schema."
}
