output "semantic_schema_name" {
  description = "Fully qualified name of the SEMANTIC schema."
  value       = "${var.database_name}.${snowflake_schema.semantic.name}"
}

output "stage_fully_qualified_name" {
  description = "Fully qualified stage name — target for PUT commands."
  value       = "${var.database_name}.${snowflake_schema.semantic.name}.${snowflake_stage.models.name}"
}

output "stage_url" {
  description = "Snowflake stage reference to pass to Cortex Analyst (`@DB.SCHEMA.STAGE`)."
  value       = "@${var.database_name}.${snowflake_schema.semantic.name}.${snowflake_stage.models.name}"
}

output "streamlit_name" {
  description = "Streamlit app name (visible in Snowsight)."
  value       = snowflake_streamlit.this.name
}

output "streamlit_fully_qualified_name" {
  description = "Fully qualified Streamlit app name."
  value       = "${var.database_name}.${snowflake_schema.semantic.name}.${snowflake_streamlit.this.name}"
}
