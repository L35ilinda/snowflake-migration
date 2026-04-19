terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Warehouses
# ---------------------------------------------------------------------------

resource "snowflake_warehouse" "this" {
  for_each = var.warehouses

  name              = each.key
  warehouse_size    = each.value.size
  auto_suspend      = each.value.auto_suspend
  auto_resume       = each.value.auto_resume ? "true" : "false"
  min_cluster_count = each.value.min_cluster_count
  max_cluster_count = each.value.max_cluster_count

  resource_monitor = lookup(local.warehouse_to_monitor, each.key, null) != null ? snowflake_resource_monitor.this[local.warehouse_to_monitor[each.key]].name : null

  initially_suspended = true

  comment = each.value.comment != "" ? each.value.comment : "${each.key} (${var.environment})."
}

locals {
  # Reverse lookup: warehouse name -> resource monitor name.
  # Built from the resource_monitors.warehouses lists.
  warehouse_to_monitor = { for pair in flatten([
    for rm_name, rm in var.resource_monitors : [
      for wh in rm.warehouses : { wh_name = wh, rm_name = rm_name }
    ]
  ]) : pair.wh_name => pair.rm_name }

  warehouse_role_grants = { for pair in flatten([
    for wh_name, wh in var.warehouses : [
      for role in wh.grant_usage_to : {
        key     = "${wh_name}_${role}"
        wh_name = wh_name
        role    = role
      }
    ]
  ]) : pair.key => pair }
}

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  for_each = local.warehouse_role_grants

  account_role_name = each.value.role
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.this[each.value.wh_name].name
  }
}

# ---------------------------------------------------------------------------
# Resource monitors
# ---------------------------------------------------------------------------

resource "snowflake_resource_monitor" "this" {
  for_each = var.resource_monitors

  name            = each.key
  credit_quota    = each.value.credit_quota
  frequency       = each.value.frequency
  start_timestamp = each.value.start_timestamp

  notify_triggers           = each.value.notify_triggers
  suspend_trigger           = each.value.suspend_trigger
  suspend_immediate_trigger = each.value.suspend_immediate_trigger
}
