output "table_names" {
  description = "Map of dataset key -> landing table name."
  value       = { for k, t in snowflake_table.landing : k => t.name }
}

output "pipe_names" {
  description = "Map of dataset key -> pipe name."
  value       = { for k, p in snowflake_pipe.this : k => p.name }
}
