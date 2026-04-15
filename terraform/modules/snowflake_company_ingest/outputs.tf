output "file_format_name" {
  value       = snowflake_file_format.csv.name
  description = "Fully-qualified CSV file format name."
}

output "stage_name" {
  value       = snowflake_stage.outbound.name
  description = "External stage name for this company's outbound feed."
}

output "stage_fully_qualified_name" {
  value       = "${var.database_name}.${var.raw_schema_name}.${snowflake_stage.outbound.name}"
  description = "Use this in LIST / COPY INTO statements."
}
