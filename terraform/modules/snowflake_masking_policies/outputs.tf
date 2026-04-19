output "policy_fully_qualified_names" {
  description = "Map of policy key -> fully qualified policy name (DB.SCHEMA.NAME)."
  value       = { for k, p in snowflake_masking_policy.this : k => "${var.database_name}.${var.schema_name}.${p.name}" }
}
