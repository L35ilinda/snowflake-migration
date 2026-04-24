output "email_integration_name" {
  value       = snowflake_email_notification_integration.this.name
  description = "Email notification integration name."
}

output "alert_name" {
  value       = snowflake_alert.this.name
  description = "Alert name."
}

output "alert_fully_qualified_name" {
  value       = "${var.database_name}.${var.schema_name}.${snowflake_alert.this.name}"
  description = "Fully qualified alert name."
}