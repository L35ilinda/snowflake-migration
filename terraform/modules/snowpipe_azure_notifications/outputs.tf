output "name" {
  description = "Snowflake notification integration name (for pipe references)."
  value       = snowflake_notification_integration.this.name
}

output "queue_uri" {
  description = "Full URI of the storage queue receiving events."
  value       = "${data.azurerm_storage_account.this.primary_queue_endpoint}${azurerm_storage_queue.snowpipe_events.name}"
}

output "queue_resource_id" {
  description = "Resource ID of the storage queue (for RBAC scoping)."
  value       = "${data.azurerm_storage_account.this.id}/queueServices/default/queues/${azurerm_storage_queue.snowpipe_events.name}"
}

# Note: the snowflakedb/snowflake provider v1.x does NOT expose
# AZURE_CONSENT_URL or AZURE_MULTI_TENANT_APP_NAME as resource attributes
# on snowflake_notification_integration (unlike snowflake_storage_integration
# which does expose them). Retrieve them after apply via:
#   DESC NOTIFICATION INTEGRATION <name>;
# Look for the AZURE_CONSENT_URL and AZURE_MULTI_TENANT_APP_NAME rows.
# See the module README for the full bootstrap sequence.
