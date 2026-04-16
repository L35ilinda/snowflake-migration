output "access_role_names" {
  description = "Map of access role key -> role name."
  value       = { for k, r in snowflake_account_role.access : k => r.name }
}

output "functional_role_names" {
  description = "Map of functional role key -> role name."
  value       = { for k, r in snowflake_account_role.functional : k => r.name }
}
