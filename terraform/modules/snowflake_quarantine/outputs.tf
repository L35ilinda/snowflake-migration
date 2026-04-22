output "table_name" {
  value       = snowflake_table.pipe_errors.name
  description = "Quarantine table name."
}

output "table_fully_qualified_name" {
  value       = "${var.database_name}.${var.schema_name}.${snowflake_table.pipe_errors.name}"
  description = "Fully qualified quarantine table name."
}

output "task_name" {
  value       = snowflake_task.capture_pipe_errors.name
  description = "Capture task name."
}
