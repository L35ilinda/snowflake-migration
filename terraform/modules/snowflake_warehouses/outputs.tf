output "warehouse_names" {
  description = "Map of warehouse key -> warehouse name."
  value       = { for k, wh in snowflake_warehouse.this : k => wh.name }
}

output "resource_monitor_names" {
  description = "Map of resource monitor key -> monitor name."
  value       = { for k, rm in snowflake_resource_monitor.this : k => rm.name }
}
